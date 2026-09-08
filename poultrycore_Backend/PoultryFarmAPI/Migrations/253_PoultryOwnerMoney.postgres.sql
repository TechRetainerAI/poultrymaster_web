-- =============================================================================
-- 253_PoultryOwnerMoney.postgres.sql
--
-- Purpose
-- -------
-- Money the owner puts INTO the farm, and money the owner takes OUT.
--
-- Today poultry records both as a free-text cash adjustment typed "Owner
-- injection" or "Withdrawal". The money reaches the cash account and reaches
-- Cash Flow, and that is all it does: there is no owner on the row, no net
-- funding figure, no reversal, and nothing that distinguishes the owner putting
-- 20,000 into the business from an opening-balance correction.
--
-- WHAT THIS IS NOT
-- ----------------
-- An owner contribution is NOT revenue and an owner draw is NOT an expense.
-- The business did not earn the first or spend the second; the owner funded it
-- and took funding back. That is why this file writes no sale, no expense, no
-- customer payment and no supplier payment -- only a cash movement and its own
-- record. If either ever reaches the P&L, this migration has failed.
--
-- ONE CASH ROW, NEVER TWO
-- -----------------------
-- Recording owner money writes exactly ONE poultrycashtransactions row and
-- moves the account balance once. The check file counts them, because the
-- classic way to get this wrong is to have both the module and a shadow
-- expense post cash for the same event.
--
-- CASH FLOW HAS TO BE TOLD
-- ------------------------
-- This is the part that is easy to miss. Poultry's Cash Flow (235) does NOT
-- read the cash-account ledger -- it deliberately cut that dependency and
-- reads business documents instead. A new table is therefore INVISIBLE to Cash
-- Flow until sppoultrycashflow_rows is given an arm that reads it, so this file
-- adds one. Without it an owner could inject 20,000, watch the bank balance
-- rise, and see nothing at all on the page that is supposed to explain where
-- the money came from.
--
-- The new arm goes BEFORE the legacy capital arm, which returns early when the
-- cashadjustment table is absent and would otherwise skip everything after it.
--
-- The two do not double count: the legacy arm reads cashadjustment, the new one
-- reads poultryownermoney, and they are different tables. Old adjustments keep
-- showing exactly as they do today. (Recording owner money through the old cash
-- adjustment dialog still works and still lands in the legacy arm -- retiring
-- that path belongs with the permissions and menu pass.)
--
-- AMOUNTS ARE STORED POSITIVE
-- ---------------------------
-- The direction lives in transactiontype, not in the sign. A contribution and
-- a draw of 5,000 both store 5,000; the cash row and the cash-flow arm apply
-- the sign. Storing a signed amount and a type is two sources of truth for the
-- same fact, and they drift.
--
-- EFFECT ON TODAY'S NUMBERS: none. A new table, new functions, and one extra
-- arm on a reader that returns nothing for it until somebody records something.
--
-- Order: after 252.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('sppoultryownermoney_record',
                             'sppoultryownermoney_reverse',
                             'sppoultryownermoney_getall',
                             'sppoultryownermoney_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The record.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryownermoney (
    poultryownermoneyid   serial PRIMARY KEY,
    farmid                varchar(450) NOT NULL,
    transactionnumber     text NULL,
    transactiondate       timestamp NOT NULL DEFAULT (now() at time zone 'utc'),

    -- The direction. Never inferred from the sign of the amount.
    transactiontype       text NOT NULL CHECK (transactiontype IN ('Contribution', 'Draw')),
    amount                numeric(14,2) NOT NULL CHECK (amount > 0),

    poultrycashaccountid  integer NOT NULL,
    paymentmethod         text NULL,

    -- Who. Both optional: a farm may have one owner and never name them, and a
    -- user id is useless on a printout, so a typed name is allowed beside it.
    owneruserid           text NULL,
    ownername             text NULL,

    referencenumber       text NULL,
    notes                 text NULL,

    status                text NOT NULL DEFAULT 'Posted'
                          CHECK (status IN ('Posted', 'Reversed')),

    -- The single cash row this wrote, and the one that undid it.
    poultrycashtransactionid  integer NULL,
    reversalcashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL
);

CREATE INDEX IF NOT EXISTS ix_poultryownermoney_farm_date
    ON poultryownermoney (farmid, transactiondate DESC);
CREATE INDEX IF NOT EXISTS ix_poultryownermoney_farm_type
    ON poultryownermoney (farmid, transactiontype, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryownermoney_number
    ON poultryownermoney (farmid, transactionnumber)
    WHERE transactionnumber IS NOT NULL;

COMMENT ON TABLE poultryownermoney IS
    'Owner contributions and draws. NOT revenue and NOT expense: the owner '
    'funded the business or took funding back. Writes exactly one cash '
    'transaction and nothing else.';
COMMENT ON COLUMN poultryownermoney.amount IS
    'Always POSITIVE. Direction comes from transactiontype; a signed amount and '
    'a type are two sources of truth for one fact.';

-- -----------------------------------------------------------------------------
-- 2. Record a contribution or a draw.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryownermoney_record(
    p_farmid               text,
    p_transactiontype      text,
    p_amount               numeric,
    p_poultrycashaccountid integer,
    p_transactiondate      timestamp DEFAULT NULL,
    p_paymentmethod        text DEFAULT NULL,
    p_owneruserid          text DEFAULT NULL,
    p_ownername            text DEFAULT NULL,
    p_referencenumber      text DEFAULT NULL,
    p_notes                text DEFAULT NULL,
    p_createdby            text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id       integer;
    v_date     timestamp := COALESCE(p_transactiondate, (now() at time zone 'utc'));
    v_balance  numeric;
    v_allowneg boolean;
    v_signed   numeric;
    v_txid     integer;
    v_type     text;
BEGIN
    IF COALESCE(p_transactiontype, '') NOT IN ('Contribution', 'Draw') THEN
        RAISE EXCEPTION 'Owner money must be a Contribution or a Draw (got "%").', p_transactiontype;
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Owner money amount must be greater than zero.';
    END IF;

    SELECT a.currentbalance, a.allownegativebalance
    INTO   v_balance, v_allowneg
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
    END IF;

    -- A draw takes money out and can overdraw; a contribution never can.
    IF p_transactiontype = 'Draw' AND v_allowneg = FALSE AND (v_balance - p_amount) < 0 THEN
        RAISE EXCEPTION 'This draw would take the cash account below zero.';
    END IF;

    INSERT INTO poultryownermoney (
        farmid, transactiondate, transactiontype, amount, poultrycashaccountid,
        paymentmethod, owneruserid, ownername, referencenumber, notes,
        status, createdby)
    VALUES (
        p_farmid, v_date, p_transactiontype, p_amount, p_poultrycashaccountid,
        NULLIF(btrim(p_paymentmethod), ''), NULLIF(btrim(p_owneruserid), ''),
        NULLIF(btrim(p_ownername), ''), NULLIF(btrim(p_referencenumber), ''),
        NULLIF(btrim(p_notes), ''), 'Posted', p_createdby)
    RETURNING poultryownermoneyid INTO v_id;

    -- Post-insert numbering, the race-free pattern this codebase uses
    -- everywhere. OWN-2026-0001 for a contribution, OWD- for a draw, so the
    -- number itself says which way the money went.
    UPDATE poultryownermoney
    SET    transactionnumber =
               CASE WHEN p_transactiontype = 'Contribution' THEN 'OWN-' ELSE 'OWD-' END
               || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  poultryownermoneyid = v_id;

    v_signed := CASE WHEN p_transactiontype = 'Contribution' THEN p_amount ELSE -p_amount END;
    v_type   := CASE WHEN p_transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END;

    -- THE one cash row. Not a sale, not an expense, not a payment.
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, p_poultrycashaccountid, v_date, v_type,
        'OwnerMoney', v_id, v_signed,
        COALESCE(NULLIF(btrim(p_notes), ''),
                 CASE WHEN p_transactiontype = 'Contribution'
                      THEN 'Owner contribution' ELSE 'Owner draw' END),
        p_createdby, p_createdby, (now() at time zone 'utc'))
    RETURNING poultrycashtransactionid INTO v_txid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_signed,
           updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = p_poultrycashaccountid;

    UPDATE poultryownermoney
    SET    poultrycashtransactionid = v_txid
    WHERE  poultryownermoneyid = v_id;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Reverse.
--
-- Append-only, like the transfer reversal: one opposite cash row, the original
-- kept, the record marked. Reversing a CONTRIBUTION takes money back out, so
-- that direction gets the overdraw guard.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryownermoney_reverse(
    p_poultryownermoneyid integer,
    p_farmid              text,
    p_reason              text,
    p_reversedby          text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_type     text;
    v_amount   numeric;
    v_acct     integer;
    v_status   text;
    v_number   text;
    v_balance  numeric;
    v_allowneg boolean;
    v_signed   numeric;
    v_txid     integer;
    v_now      timestamp := (now() at time zone 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse owner money.';
    END IF;

    SELECT o.transactiontype, o.amount, o.poultrycashaccountid, o.status, o.transactionnumber
    INTO   v_type, v_amount, v_acct, v_status, v_number
    FROM   poultryownermoney o
    WHERE  o.poultryownermoneyid = p_poultryownermoneyid AND o.farmid = p_farmid;

    IF v_type IS NULL THEN
        RAISE EXCEPTION 'Owner money record % not found.', p_poultryownermoneyid;
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted owner money record can be reversed (this one is %).', v_status;
    END IF;

    -- Undoing a contribution moves money OUT again.
    v_signed := CASE WHEN v_type = 'Contribution' THEN -v_amount ELSE v_amount END;

    IF v_signed < 0 THEN
        SELECT a.currentbalance, a.allownegativebalance
        INTO   v_balance, v_allowneg
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = v_acct;
        IF v_allowneg = FALSE AND (v_balance + v_signed) < 0 THEN
            RAISE EXCEPTION 'The cash account no longer holds this contribution; reversing it would overdraw the account.';
        END IF;
    END IF;

    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, v_acct, v_now,
        CASE WHEN v_type = 'Contribution' THEN 'OwnerContributionReversal' ELSE 'OwnerDrawReversal' END,
        'OwnerMoney', p_poultryownermoneyid, v_signed,
        'Reversal of ' || COALESCE(v_number, p_poultryownermoneyid::text),
        p_reversedby, p_reversedby, v_now)
    RETURNING poultrycashtransactionid INTO v_txid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_signed, updatedat = v_now
    WHERE  a.poultrycashaccountid = v_acct;

    UPDATE poultryownermoney o
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = btrim(p_reason), reversalcashtransactionid = v_txid
    WHERE  o.poultryownermoneyid = p_poultryownermoneyid AND o.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Reads.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryownermoney_getall(
    p_farmid text,
    p_type   text DEFAULT NULL,
    p_from   date DEFAULT NULL,
    p_to     date DEFAULT NULL,
    p_status text DEFAULT NULL
) RETURNS TABLE(
    poultryownermoneyid       integer,
    farmid                    text,
    transactionnumber         text,
    transactiondate           timestamp,
    transactiontype           text,
    amount                    numeric,
    poultrycashaccountid      integer,
    accountname               text,
    paymentmethod             text,
    owneruserid               text,
    ownername                 text,
    referencenumber           text,
    notes                     text,
    status                    text,
    poultrycashtransactionid  integer,
    reversalcashtransactionid integer,
    createdby                 text,
    createdat                 timestamp,
    reversedby                text,
    reversedat                timestamp,
    reversalreason            text
)
LANGUAGE sql STABLE
AS $function$
    SELECT o.poultryownermoneyid, o.farmid::text, o.transactionnumber::text,
           o.transactiondate, o.transactiontype::text, o.amount,
           o.poultrycashaccountid, a.accountname::text,
           o.paymentmethod::text, o.owneruserid::text, o.ownername::text,
           o.referencenumber::text, o.notes::text, o.status::text,
           o.poultrycashtransactionid, o.reversalcashtransactionid,
           o.createdby::text, o.createdat,
           o.reversedby::text, o.reversedat, o.reversalreason::text
    FROM   poultryownermoney o
    LEFT   JOIN poultrycashaccounts a
           ON a.poultrycashaccountid = o.poultrycashaccountid
    WHERE  o.farmid = p_farmid
      AND  (p_type   IS NULL OR p_type = 'All'   OR o.transactiontype = p_type)
      AND  (p_status IS NULL OR p_status = 'All' OR o.status = p_status)
      AND  (p_from IS NULL OR o.transactiondate >= p_from::timestamp)
      AND  (p_to   IS NULL OR o.transactiondate <  (p_to + 1)::timestamp)
    ORDER  BY o.transactiondate DESC, o.poultryownermoneyid DESC;
$function$;

-- The five cards on the page. Reversed records are excluded from every total:
-- money that was put in and taken back out is not funding.
CREATE OR REPLACE FUNCTION public.sppoultryownermoney_summary(
    p_farmid text,
    p_from   date DEFAULT NULL,
    p_to     date DEFAULT NULL
) RETURNS TABLE(
    totalcontributions  numeric,
    totaldraws          numeric,
    netfunding          numeric,
    periodcontributions numeric,
    perioddraws         numeric,
    contributioncount   integer,
    drawcount           integer
)
LANGUAGE sql STABLE
AS $function$
    WITH live AS (
        SELECT o.transactiontype, o.amount, o.transactiondate
        FROM   poultryownermoney o
        WHERE  o.farmid = p_farmid AND o.status = 'Posted'
    ),
    inperiod AS (
        SELECT l.* FROM live l
        WHERE  (p_from IS NULL OR l.transactiondate >= p_from::timestamp)
          AND  (p_to   IS NULL OR l.transactiondate <  (p_to + 1)::timestamp)
    )
    SELECT
        COALESCE(SUM(amount) FILTER (WHERE transactiontype = 'Contribution'), 0)::numeric(14,2),
        COALESCE(SUM(amount) FILTER (WHERE transactiontype = 'Draw'), 0)::numeric(14,2),
        (COALESCE(SUM(amount) FILTER (WHERE transactiontype = 'Contribution'), 0)
         - COALESCE(SUM(amount) FILTER (WHERE transactiontype = 'Draw'), 0))::numeric(14,2),
        (SELECT COALESCE(SUM(amount) FILTER (WHERE transactiontype = 'Contribution'), 0)::numeric(14,2) FROM inperiod),
        (SELECT COALESCE(SUM(amount) FILTER (WHERE transactiontype = 'Draw'), 0)::numeric(14,2) FROM inperiod),
        COUNT(*) FILTER (WHERE transactiontype = 'Contribution')::int,
        COUNT(*) FILTER (WHERE transactiontype = 'Draw')::int
    FROM live;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Cash Flow learns to read it.
--
-- Reproduced from the LIVE definition of sppoultrycashflow_rows. Every existing
-- arm -- receipts, counter cash, expenses, later supplier payments, legacy
-- adjustments -- is byte for byte what it was; the only change is the new arm
-- above the legacy capital one, and the renumbering of that comment.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_tbl  text;
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. customer receipts, dated when the money arrived -----------------
    -- This is the leg that makes it a CASH flow rather than a sales report. A
    -- January sale part-paid in August belongs in August, and poultrypayments is
    -- the only place that date exists (145_PoultryPayments.sql:36).
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           p.poultrypaymentid,
           NULL::integer,
           NULL::text,
           p.paymentdate,
           'CashIn'::text,
           'CustomerPayment'::text,
           p.saleid,
           FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(p.note), ''),
                    NULLIF(btrim(p.reference), ''),
                    'Payment for sale #' || p.saleid::text)::text,
           'OperatingIn'::text
    FROM   poultrypayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      -- A REVERSED payment is money that came back. 222/227 added this column and
      -- flip it on reversal rather than deleting the row, so without this filter
      -- the report counts a refunded receipt as income for ever.
      AND  COALESCE(p.status, 'Posted') = 'Posted' 
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to;

    -- ---- 2. the part paid at the counter -----------------------------------
    -- Not every receipt becomes a payment row: a sale entered as already paid
    -- sets amountpaid directly. Counting the difference here picks those up
    -- without double counting the ones that DID create a row.
    --
    -- `paid` is honoured ahead of amountpaid because older rows were marked paid
    -- without amountpaid ever being populated -- the same rule CashController
    -- applies. Without it, historic cash sales vanish from the report.
    RETURN QUERY
    SELECT 'SaleResidual'::text,
           FALSE,
           s.saleid,
           s.poultrycashaccountid,
           NULL::text,
           -- sale.saledate is DATE while this function returns TIMESTAMP, so the
           -- cast is load-bearing: without it Postgres refuses the whole
           -- function with "structure of query does not match function result
           -- type". The live 235 carries this; the copy of 235 in this repo does
           -- NOT, so anyone reproducing that file inherits the fault.
           s.saledate::timestamp,
           'CashIn'::text,
           'Sale'::text,
           s.saleid,
           FALSE,
           v.residual,
           ('Sale #' || s.saleid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.customername), ''), ''))::text,
           'OperatingIn'::text
    FROM   sale s
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paid, false)
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   poultrypayments pp
                             WHERE  pp.saleid = s.saleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               -- Same reason: a reversed payment never covered
                               -- anything, so it must not reduce the residual.
                               AND  COALESCE(pp.status, 'Posted') = 'Posted'), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      -- Only a POSITIVE residual. A negative one means the payment rows already
      -- exceed what the sale records as paid, which is a data inconsistency; it
      -- is surfaced by this file's verification query rather than quietly
      -- subtracted from the day's income.
      AND  v.residual > 0
      AND  s.saledate >= v_from
      AND  s.saledate <= v_to;

    -- ---- 3. money paid out when the expense was recorded --------------------
    -- Every kind of spending, because every module writes here. NonCash is still
    -- the only category-level exclusion: internal use posts it to record stock
    -- leaving without any money moving (migration 216).
    --
    -- What changed from 235 is the AMOUNT. It was e.amount -- the full bill.
    -- It is now what was actually paid at entry: the expense's resolved
    -- amountpaid, less anything a supplier payment has since covered (which the
    -- next arm reports on its own, later, date).
    --
    -- amountpaid IS NULL means paid in full, so a legacy row resolves straight
    -- back to e.amount and this arm returns exactly what 235 returned.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           e.expenseid,
           e.poultrycashaccountid,
           NULL::text,
           e.expensedate,
           'CashOut'::text,
           'Expense'::text,
           e.expenseid,
           FALSE,
           -v.paidatentry,
           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,
           'OperatingOut'::text
    FROM   expense e
    CROSS  JOIN LATERAL (
        SELECT GREATEST(
                   COALESCE(e.amountpaid, e.amount)
                 - COALESCE((SELECT SUM(sa.amountapplied)
                             FROM   supplierpaymentallocation sa
                             WHERE  sa.farmid = p_farmid
                               AND  sa.module = 'poultry'
                               AND  sa.status = 'Posted'
                               AND  sa.documenttype = 'Expense'
                               AND  sa.documentid = e.expenseid), 0)
               , 0)::numeric AS paidatentry
    ) v
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  v.paidatentry > 0
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  e.expensedate >= v_from
      AND  e.expensedate <= v_to;

    -- ---- 3b. money paid out later, against a bill already recorded ----------
    -- A supplier payment settling an unpaid expense. It belongs to the day the
    -- money moved, not the day the bill was entered -- the same principle arm 1
    -- applies to customer receipts.
    --
    -- sourceid is the EXPENSE id so the row still drills through to the bill it
    -- paid (and so _detail's category join finds it); sourcerowid is the
    -- allocation id, which is what makes each row unique.
    --
    -- Only documenttype='Expense'. A payment against a raw-material purchase or
    -- a flock batch books its own expense row dated the payment date (224:414)
    -- and is already counted by arm 3; adding it here would double it.
    RETURN QUERY
    SELECT 'ExpensePayment'::text,
           FALSE,
           sa.allocationid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'ExpensePayment'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment for expense #' || sa.documentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON  sp.poultrysupplierpaymentid = sa.paymentid
           AND sp.farmid = sa.farmid
    LEFT   JOIN supplier s
           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'Expense'
      AND  sp.status = 'Posted'
      AND  sa.amountapplied <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 4. owner money (253) ----------------------------------------------
    -- Contributions and draws recorded through the Owner Money module.
    -- FINANCING, not operating: the owner funded the business or took funding
    -- back. Never revenue, never expense.
    --
    -- Reversed records are dropped entirely rather than netted to zero with a
    -- second row -- a contribution that was put in and taken back out is not
    -- funding, and showing both legs would put money the business never kept
    -- into Money In and Money Out.
    --
    -- Placed ABOVE the legacy capital arm on purpose: that arm RETURNs early
    -- when cashadjustment is absent, so anything below it is skipped on a farm
    -- with no capital records.
    RETURN QUERY
    SELECT 'OwnerMoney'::text,
           FALSE,
           o.poultryownermoneyid,
           o.poultrycashaccountid,
           a.accountname::text,
           o.transactiondate,
           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,
           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,
           o.poultryownermoneyid,
           FALSE,
           -- Stored positive; the sign is applied here, once.
           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,
           COALESCE(NULLIF(btrim(o.notes), ''),
                    NULLIF(btrim(o.ownername), ''),
                    CASE WHEN o.transactiontype = 'Contribution'
                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,
           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text
    FROM   poultryownermoney o
    LEFT   JOIN poultrycashaccounts a
           ON a.poultrycashaccountid = o.poultrycashaccountid
    WHERE  o.farmid = p_farmid
      AND  o.status = 'Posted'
      AND  o.transactiondate >= v_from
      AND  o.transactiondate <= v_to;

    -- ---- 5. capital in and out (legacy cash adjustments) --------------------
    -- Owner injections, loans received, withdrawals. Financing, not operating:
    -- money the business received or returned rather than earned or spent.
    --
    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything
    -- below it would be silently skipped on a farm without capital records.
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);

    IF v_tbl IS NULL THEN
        RETURN;                     -- no capital records; the four legs stand
    END IF;

    RETURN QUERY EXECUTE format($sql$
        SELECT 'Adjustment'::text,
               FALSE,
               ca.adjustmentid,
               NULL::integer,
               NULL::text,
               ca.adjustmentdate,
               CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,
               COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,
               ca.adjustmentid,
               FALSE,
               ca.amount::numeric,     -- already signed
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,
               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text
        FROM   %s ca
        WHERE  lower(ca.farmid::text) = lower($1)
          AND  ca.amount <> 0
          AND  ca.adjustmentdate >= $2
          AND  ca.adjustmentdate <= $3
    $sql$, v_tbl)
    USING p_farmid, v_from, v_to;
END;
$function$;

COMMIT;

-- =============================================================================
-- 258_WaterOwnerMoney.postgres.sql
--
-- Purpose
-- -------
-- Money the owner puts INTO the company, and money the owner takes OUT.
-- The water twin of 253.
--
-- Today water records both as a free-text cash-account adjustment. The money
-- reaches the cash account and that is all it does: there is no owner on the
-- row, no net funding figure, no reversal, and nothing distinguishing the owner
-- putting 20,000 into the business from an opening-balance correction.
--
-- Worse than on poultry, in fact. Migration 236 wrote the problem down in its
-- own header and left it:
--
--     "Water records owner injections and similar through adjustWaterCashAccount,
--      which writes to the cash LEDGER. This report does not read the ledger, so
--      those movements will NOT appear in Water's financing section. ...
--      Giving Water its own capital record is a separate decision."
--
-- This file is that decision. Until now an owner could inject 20,000 into a
-- water company, watch the bank balance rise, and see nothing whatsoever on the
-- page that is supposed to explain where the money came from.
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
-- Recording owner money writes exactly ONE watercashtransactions row and moves
-- the account balance once. The check file counts them, because the classic way
-- to get this wrong is to have both the module and a shadow expense post cash
-- for the same event.
--
-- CASH FLOW HAS TO BE TOLD
-- ------------------------
-- Water's Cash Flow (236) does NOT read the cash-account ledger -- it
-- deliberately cut that dependency and reads business documents instead. A new
-- table is therefore INVISIBLE to Cash Flow until spwatercashflow_rows is given
-- an arm that reads it, so this file adds one.
--
-- The new arm goes BEFORE the legacy capital arm, which returns early when the
-- cashadjustment table is absent and would otherwise skip everything after it.
--
-- The two do not double count: the legacy arm reads cashadjustment, the new one
-- reads waterownermoney, and they are different tables. Old adjustments keep
-- showing exactly as they do today.
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
-- Order: after 257.
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
          AND  p.proname IN ('spwaterownermoney_record',
                             'spwaterownermoney_reverse',
                             'spwaterownermoney_getall',
                             'spwaterownermoney_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The record.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS waterownermoney (
    waterownermoneyid     serial PRIMARY KEY,
    farmid                varchar(450) NOT NULL,
    transactionnumber     text NULL,
    transactiondate       timestamp NOT NULL DEFAULT (now() at time zone 'utc'),

    -- The direction. Never inferred from the sign of the amount.
    transactiontype       text NOT NULL CHECK (transactiontype IN ('Contribution', 'Draw')),
    amount                numeric(14,2) NOT NULL CHECK (amount > 0),

    watercashaccountid    integer NOT NULL,
    paymentmethod         text NULL,

    -- Who. Both optional: a company may have one owner and never name them, and
    -- a user id is useless on a printout, so a typed name is allowed beside it.
    owneruserid           text NULL,
    ownername             text NULL,

    referencenumber       text NULL,
    notes                 text NULL,

    status                text NOT NULL DEFAULT 'Posted'
                          CHECK (status IN ('Posted', 'Reversed')),

    -- The single cash row this wrote, and the one that undid it.
    watercashtransactionid    integer NULL,
    reversalcashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL
);

CREATE INDEX IF NOT EXISTS ix_waterownermoney_farm_date
    ON waterownermoney (farmid, transactiondate DESC);
CREATE INDEX IF NOT EXISTS ix_waterownermoney_farm_type
    ON waterownermoney (farmid, transactiontype, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_waterownermoney_number
    ON waterownermoney (farmid, transactionnumber)
    WHERE transactionnumber IS NOT NULL;

COMMENT ON TABLE waterownermoney IS
    'Owner contributions and draws. NOT revenue and NOT expense: the owner '
    'funded the business or took funding back. Writes exactly one cash '
    'transaction and nothing else. Closes the capital gap 236 recorded.';
COMMENT ON COLUMN waterownermoney.amount IS
    'Always POSITIVE. Direction comes from transactiontype; a signed amount and '
    'a type are two sources of truth for one fact.';

-- -----------------------------------------------------------------------------
-- 2. Record a contribution or a draw.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterownermoney_record(
    p_farmid             text,
    p_transactiontype    text,
    p_amount             numeric,
    p_watercashaccountid integer,
    p_transactiondate    timestamp DEFAULT NULL,
    p_paymentmethod      text DEFAULT NULL,
    p_owneruserid        text DEFAULT NULL,
    p_ownername          text DEFAULT NULL,
    p_referencenumber    text DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_createdby          text DEFAULT NULL
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
    FROM   watercashaccounts a
    WHERE  a.watercashaccountid = p_watercashaccountid AND a.farmid = p_farmid;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Cash account does not exist or does not belong to this company.';
    END IF;

    -- A draw takes money out and can overdraw; a contribution never can.
    IF p_transactiontype = 'Draw' AND v_allowneg = FALSE AND (v_balance - p_amount) < 0 THEN
        RAISE EXCEPTION 'This draw would take the cash account below zero.';
    END IF;

    INSERT INTO waterownermoney (
        farmid, transactiondate, transactiontype, amount, watercashaccountid,
        paymentmethod, owneruserid, ownername, referencenumber, notes,
        status, createdby)
    VALUES (
        p_farmid, v_date, p_transactiontype, p_amount, p_watercashaccountid,
        NULLIF(btrim(p_paymentmethod), ''), NULLIF(btrim(p_owneruserid), ''),
        NULLIF(btrim(p_ownername), ''), NULLIF(btrim(p_referencenumber), ''),
        NULLIF(btrim(p_notes), ''), 'Posted', p_createdby)
    RETURNING waterownermoneyid INTO v_id;

    -- Post-insert numbering, the race-free pattern this codebase uses
    -- everywhere. OWN-2026-0001 for a contribution, OWD- for a draw, so the
    -- number itself says which way the money went.
    UPDATE waterownermoney
    SET    transactionnumber =
               CASE WHEN p_transactiontype = 'Contribution' THEN 'OWN-' ELSE 'OWD-' END
               || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  waterownermoneyid = v_id;

    v_signed := CASE WHEN p_transactiontype = 'Contribution' THEN p_amount ELSE -p_amount END;
    v_type   := CASE WHEN p_transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END;

    -- THE one cash row. Not a sale, not an expense, not a payment.
    INSERT INTO watercashtransactions (
        farmid, watercashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, p_watercashaccountid, v_date, v_type,
        'OwnerMoney', v_id, v_signed,
        COALESCE(NULLIF(btrim(p_notes), ''),
                 CASE WHEN p_transactiontype = 'Contribution'
                      THEN 'Owner contribution' ELSE 'Owner draw' END),
        p_createdby, p_createdby, (now() at time zone 'utc'))
    RETURNING watercashtransactionid INTO v_txid;

    UPDATE watercashaccounts a
    SET    currentbalance = a.currentbalance + v_signed,
           updatedat = (now() at time zone 'utc')
    WHERE  a.watercashaccountid = p_watercashaccountid;

    UPDATE waterownermoney
    SET    watercashtransactionid = v_txid
    WHERE  waterownermoneyid = v_id;

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
CREATE OR REPLACE FUNCTION public.spwaterownermoney_reverse(
    p_waterownermoneyid integer,
    p_farmid            text,
    p_reason            text,
    p_reversedby        text DEFAULT NULL
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

    SELECT o.transactiontype, o.amount, o.watercashaccountid, o.status, o.transactionnumber
    INTO   v_type, v_amount, v_acct, v_status, v_number
    FROM   waterownermoney o
    WHERE  o.waterownermoneyid = p_waterownermoneyid AND o.farmid = p_farmid;

    IF v_type IS NULL THEN
        RAISE EXCEPTION 'Owner money record % not found.', p_waterownermoneyid;
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted owner money record can be reversed (this one is %).', v_status;
    END IF;

    -- Undoing a contribution moves money OUT again.
    v_signed := CASE WHEN v_type = 'Contribution' THEN -v_amount ELSE v_amount END;

    IF v_signed < 0 THEN
        SELECT a.currentbalance, a.allownegativebalance
        INTO   v_balance, v_allowneg
        FROM   watercashaccounts a
        WHERE  a.watercashaccountid = v_acct;
        IF v_allowneg = FALSE AND (v_balance + v_signed) < 0 THEN
            RAISE EXCEPTION 'The cash account no longer holds this contribution; reversing it would overdraw the account.';
        END IF;
    END IF;

    INSERT INTO watercashtransactions (
        farmid, watercashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, v_acct, v_now,
        CASE WHEN v_type = 'Contribution' THEN 'OwnerContributionReversal' ELSE 'OwnerDrawReversal' END,
        'OwnerMoney', p_waterownermoneyid, v_signed,
        'Reversal of ' || COALESCE(v_number, p_waterownermoneyid::text),
        p_reversedby, p_reversedby, v_now)
    RETURNING watercashtransactionid INTO v_txid;

    UPDATE watercashaccounts a
    SET    currentbalance = a.currentbalance + v_signed, updatedat = v_now
    WHERE  a.watercashaccountid = v_acct;

    UPDATE waterownermoney o
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = btrim(p_reason), reversalcashtransactionid = v_txid
    WHERE  o.waterownermoneyid = p_waterownermoneyid AND o.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Reads.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterownermoney_getall(
    p_farmid text,
    p_type   text DEFAULT NULL,
    p_from   date DEFAULT NULL,
    p_to     date DEFAULT NULL,
    p_status text DEFAULT NULL
) RETURNS TABLE(
    waterownermoneyid         integer,
    farmid                    text,
    transactionnumber         text,
    transactiondate           timestamp,
    transactiontype           text,
    amount                    numeric,
    watercashaccountid        integer,
    accountname               text,
    paymentmethod             text,
    owneruserid               text,
    ownername                 text,
    referencenumber           text,
    notes                     text,
    status                    text,
    watercashtransactionid    integer,
    reversalcashtransactionid integer,
    createdby                 text,
    createdat                 timestamp,
    reversedby                text,
    reversedat                timestamp,
    reversalreason            text
)
LANGUAGE sql STABLE
AS $function$
    SELECT o.waterownermoneyid, o.farmid::text, o.transactionnumber::text,
           o.transactiondate, o.transactiontype::text, o.amount,
           o.watercashaccountid, a.accountname::text,
           o.paymentmethod::text, o.owneruserid::text, o.ownername::text,
           o.referencenumber::text, o.notes::text, o.status::text,
           o.watercashtransactionid, o.reversalcashtransactionid,
           o.createdby::text, o.createdat,
           o.reversedby::text, o.reversedat, o.reversalreason::text
    FROM   waterownermoney o
    LEFT   JOIN watercashaccounts a
           ON a.watercashaccountid = o.watercashaccountid
    WHERE  o.farmid = p_farmid
      AND  (p_type   IS NULL OR p_type = 'All'   OR o.transactiontype = p_type)
      AND  (p_status IS NULL OR p_status = 'All' OR o.status = p_status)
      AND  (p_from IS NULL OR o.transactiondate >= p_from::timestamp)
      AND  (p_to   IS NULL OR o.transactiondate <  (p_to + 1)::timestamp)
    ORDER  BY o.transactiondate DESC, o.waterownermoneyid DESC;
$function$;

-- The five cards on the page. Reversed records are excluded from every total:
-- money that was put in and taken back out is not funding.
CREATE OR REPLACE FUNCTION public.spwaterownermoney_summary(
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
        FROM   waterownermoney o
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
-- Reproduced from the LIVE definition of spwatercashflow_rows. Every existing
-- arm -- receipts, counter cash, expenses, later supplier payments, legacy
-- adjustments -- is byte for byte what it was; the only change is the new arm
-- above the legacy capital one, and the renumbering of that comment.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
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
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           p.waterpaymentid,
           NULL::integer,
           NULL::text,
           p.paymentdate,
           'CashIn'::text,
           'CustomerPayment'::text,
           p.watersaleid,
           FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(p.note), ''),
                    NULLIF(btrim(p.reference), ''),
                    'Payment for sale #' || p.watersaleid::text)::text,
           'OperatingIn'::text
    FROM   waterpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      -- A REVERSED payment is money that came back. 227 added this column and
      -- flips it on reversal rather than deleting the row, so without this filter
      -- the report counts a refunded receipt as income for ever.
      AND  COALESCE(p.status, 'Posted') = 'Posted'
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to;

    -- ---- 2. the part paid at the point of sale -----------------------------
    -- Same reasoning as 235: a sale settled on the spot may never create a
    -- payment row, and the difference is what picks those up.
    RETURN QUERY
    SELECT 'SaleResidual'::text,
           FALSE,
           s.watersaleid,
           NULL::integer,
           NULL::text,
           s.saledate,
           'CashIn'::text,
           'Sale'::text,
           s.watersaleid,
           FALSE,
           v.residual,
           ('Sale #' || s.watersaleid::text)::text,
           'OperatingIn'::text
    FROM   watersales s
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.status, '') = 'Paid'
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(wp.amount)
                             FROM   waterpayments wp
                             WHERE  wp.watersaleid = s.watersaleid
                               AND  lower(wp.farmid::text) = lower(p_farmid)
                               -- Same reason: a reversed payment never covered
                               -- anything, so it must not reduce the residual.
                               AND  COALESCE(wp.status, 'Posted') = 'Posted'), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      -- A cancelled sale is not income, whatever it once recorded as paid.
      AND  COALESCE(s.status, '') <> 'Cancelled'
      AND  v.residual > 0
      AND  s.saledate >= v_from
      AND  s.saledate <= v_to;

    -- ---- 3. money paid out when the bill was recorded -----------------------
    -- 236's gates are kept verbatim -- Approved, not deleted -- with two
    -- changes:
    --
    --   * the AMOUNT is what was actually paid at entry, not the whole bill:
    --     the resolved amountpaid, less anything a supplier payment has since
    --     covered (which the next arm reports on its own, later, date);
    --   * the `paymentmethod <> 'Credit'` filter is GONE, because the resolution
    --     subsumes it. A Credit bill resolves to 0 paid and drops out on
    --     `paidatentry > 0` instead -- same rows excluded, and a Credit bill
    --     that has since been part-paid is no longer wrongly invisible.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           e.waterexpenseid,
           e.watercashaccountid,
           NULL::text,
           e.expensedate,
           'CashOut'::text,
           'Expense'::text,
           e.waterexpenseid,
           FALSE,
           -v.paidatentry,
           COALESCE(NULLIF(btrim(e.description), ''),
                    NULLIF(btrim(e.paidto), ''),
                    'Expense #' || e.waterexpenseid::text)::text,
           'OperatingOut'::text
    FROM   waterexpenses e
    CROSS  JOIN LATERAL (
        SELECT GREATEST(
                   COALESCE(e.amountpaid,
                            CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                                 THEN 0 ELSE e.amount END)
                 - COALESCE((SELECT SUM(sa.amountapplied)
                             FROM   supplierpaymentallocation sa
                             WHERE  sa.farmid = p_farmid
                               AND  sa.module = 'water'
                               AND  sa.status = 'Posted'
                               AND  sa.documenttype = 'Expense'
                               AND  sa.documentid = e.waterexpenseid), 0)
               , 0)::numeric AS paidatentry
    ) v
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.isdeleted, false) = false
      AND  v.paidatentry > 0
      -- 047's rule: only an approved expense has been recognised at all.
      AND  COALESCE(e.status, '') = 'Approved'
      AND  e.expensedate >= v_from
      AND  e.expensedate <= v_to;

    -- ---- 3b. money paid out later, against a bill already recorded ----------
    -- A supplier payment settling a bill. It belongs to the day the money moved,
    -- not the day the bill was entered.
    --
    -- Only documenttype='Expense'. A payment against a raw-material purchase
    -- books its own aggregated expense row dated the payment date (240) and is
    -- already counted by arm 3; adding it here would double it.
    RETURN QUERY
    SELECT 'ExpensePayment'::text,
           FALSE,
           sa.allocationid,
           sp.watercashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'ExpensePayment'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment for expense #' || sa.documentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingOut'::text
    FROM   supplierpaymentallocation sa
    JOIN   watersupplierpayments sp
           ON  sp.watersupplierpaymentid = sa.paymentid
           AND sp.farmid = sa.farmid
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'water'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'Expense'
      AND  COALESCE(sp.status, 'Posted') = 'Posted'
      AND  sa.amountapplied <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 4. owner money (258) ----------------------------------------------
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
    -- when cashadjustment is absent, so anything below it is skipped on a
    -- company with no capital records.
    RETURN QUERY
    SELECT 'OwnerMoney'::text,
           FALSE,
           o.waterownermoneyid,
           o.watercashaccountid,
           a.accountname::text,
           o.transactiondate,
           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,
           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,
           o.waterownermoneyid,
           FALSE,
           -- Stored positive; the sign is applied here, once.
           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,
           COALESCE(NULLIF(btrim(o.notes), ''),
                    NULLIF(btrim(o.ownername), ''),
                    CASE WHEN o.transactiontype = 'Contribution'
                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,
           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text
    FROM   waterownermoney o
    LEFT   JOIN watercashaccounts a
           ON a.watercashaccountid = o.watercashaccountid
    WHERE  o.farmid = p_farmid
      AND  o.status = 'Posted'
      AND  o.transactiondate >= v_from
      AND  o.transactiondate <= v_to;

    -- ---- 5. capital in and out (legacy cash adjustments) --------------------
    -- Expected to return nothing on Water today -- see 236's header note.
    --
    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything
    -- below it would be silently skipped.
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);

    IF v_tbl IS NULL THEN
        RETURN;
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
               ca.amount::numeric,
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

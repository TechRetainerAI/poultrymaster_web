-- =============================================================================
-- 287_PoultryOwnerMoneyReadsCashAdjustments.postgres.sql
--
-- Purpose
-- -------
-- Make the Owner Money page show the owner injections and withdrawals that were
-- recorded on the Cash and Cash Flow pages.
--
-- THE GAP
-- =======
-- There are two ways to record the owner putting money in, and they write to
-- different tables:
--
--   /cash and /cash-flow   POST /Cash/Adjustment -> cashadjustment,
--                          adjustmenttype 'OwnerInjection' or 'Withdrawal'
--   /poultry-owner-money   sppoultryownermoney_record -> poultryownermoney
--
-- Cash Flow reads BOTH -- 253 added an arm for poultryownermoney and left the
-- legacy cashadjustment arm alone -- so an owner sees every injection there.
-- The Owner Money page reads only poultryownermoney, so the same injection is
-- missing from the page whose entire job is to explain where the money came
-- from. An owner who has always used the Cash page sees an empty capital record
-- and a Cash Flow full of financing.
--
-- WHAT THIS FILE DOES
-- ===================
-- Widens the two READS -- _getall and _summary -- to union in the matching
-- cashadjustment rows. It writes nothing, moves no money, and creates no table.
--
-- CASH FLOW IS NOT TOUCHED, AND THAT IS THE POINT
-- ===============================================
-- The obvious alternative -- copying cashadjustment rows into poultryownermoney
-- -- would double-count immediately: Cash Flow reads both tables, so the same
-- injection would appear twice in the financing section. Reading across at
-- report time keeps one row, one place, one number.
--
-- THE ROWS ARE READ-ONLY HERE
-- ===========================
-- A cashadjustment row belongs to the Cash page, which edits and deletes it.
-- Owner Money is append-only: it reverses by writing an opposite cash row and
-- marking the original. Those two lifecycles do not mix, so the legacy rows come
-- back with source = 'CashAdjustment' and the page hides Reverse on them. Trying
-- to reverse one from here would either write a cash row the Cash page knows
-- nothing about, or silently fail.
--
-- WHICH ADJUSTMENTS COUNT, AND WHY THE SIGN DECIDES THE DIRECTION
-- ===============================================================
-- Only 'OwnerInjection' and 'Withdrawal'. Deliberately NOT:
--
--   LoanReceived    borrowed money, not owner money. The Loans module (254)
--                   owns it, and counting it here would state the same money
--                   twice across two pages.
--   OpeningBalance  the account's starting position, not funding put in.
--   Correction      a bookkeeping fix, not a capital event.
--
-- The TYPE decides whether a row is owner money; the SIGN decides which way it
-- went. That is exactly how sppoultrycashflow_rows already reads the same table
-- (`CASE WHEN ca.amount >= 0 THEN 'CashIn'`), so the two pages cannot disagree
-- about a row -- and it stays right when somebody records a correction to an
-- injection as a negative 'OwnerInjection', which classifying by type alone
-- would report as money going IN.
--
-- Amounts are emitted POSITIVE with the direction in transactiontype, matching
-- how poultryownermoney stores its own rows (253: "the direction lives in
-- transactiontype, not in the sign").
--
-- EFFECT ON TODAY'S NUMBERS
-- =========================
-- The Owner Money page's totals WILL move, and that is the requested change:
-- injections that were always in Cash Flow now also appear in the capital
-- record. Nothing else moves -- Cash Flow, the P&L, cash balances and the
-- ledger are all untouched, because this file only reads.
--
-- Order: after 286.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- Both functions gain return columns, and CREATE OR REPLACE cannot change a
-- return type. Leaving the old one in place would let Npgsql bind either.
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
          AND  p.proname IN ('sppoultryownermoney_getall',
                             'sppoultryownermoney_summary',
                             'fnpoultryownermoney_legacy')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The legacy rows, in owner-money shape.
--
-- One place, so _getall and _summary cannot disagree about which adjustments
-- count or which way they went.
--
-- The table is resolved at run time because it is `cashadjustment` on some
-- environments and `cashadjustments` on others -- 235 and 236 both do the same
-- COALESCE. A company with neither gets an empty set rather than an error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryownermoney_legacy(p_farmid text)
RETURNS TABLE(
    adjustmentid    integer,
    transactiondate timestamp,
    transactiontype text,
    amount          numeric,
    description     text,
    createdby       text,
    createdat       timestamp
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_tbl text;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY EXECUTE format($sql$
        SELECT ca.adjustmentid,
               ca.adjustmentdate::timestamp,
               CASE WHEN ca.amount >= 0 THEN 'Contribution' ELSE 'Draw' END::text,
               abs(ca.amount)::numeric,
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,
               ca.userid::text,
               ca.createddate::timestamp
        FROM   %s ca
        WHERE  lower(ca.farmid::text) = lower($1)
          AND  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
          AND  ca.amount <> 0
    $sql$, v_tbl)
    USING p_farmid;
END;
$function$;

COMMENT ON FUNCTION public.fnpoultryownermoney_legacy(text) IS
    'Owner injections and withdrawals recorded on the Cash / Cash Flow pages, '
    'shaped like owner-money rows. Type selects, sign decides direction, amount '
    'is positive. Read-only: the Cash page owns these rows.';

-- -----------------------------------------------------------------------------
-- 2. The list.
--
-- Reproduced from 253 with the legacy arm unioned on and two columns added:
--
--   source    'OwnerMoney' | 'CashAdjustment' -- what the page keys on and what
--             it uses to decide whether Reverse is offered
--   sourceid  the id WITHIN that source
--
-- poultryownermoneyid stays the real id for owner-money rows and is 0 for
-- legacy ones. It is deliberately NOT reused to carry an adjustment id: the two
-- id spaces overlap, and a page keying rows on it would collide and offer
-- Reverse against the wrong record.
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
    reversalreason            text,
    source                    text,
    sourceid                  integer
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
           o.reversedby::text, o.reversedat, o.reversalreason::text,
           'OwnerMoney'::text, o.poultryownermoneyid
    FROM   poultryownermoney o
    LEFT   JOIN poultrycashaccounts a
           ON a.poultrycashaccountid = o.poultrycashaccountid
    WHERE  o.farmid = p_farmid
      AND  (p_type   IS NULL OR p_type = 'All'   OR o.transactiontype = p_type)
      AND  (p_status IS NULL OR p_status = 'All' OR o.status = p_status)
      AND  (p_from IS NULL OR o.transactiondate >= p_from::timestamp)
      AND  (p_to   IS NULL OR o.transactiondate <  (p_to + 1)::timestamp)

    UNION ALL

    -- Recorded on the Cash / Cash Flow pages. Always 'Posted': a cashadjustment
    -- has no reversal state -- the Cash page edits or deletes it outright -- so
    -- a request filtered to 'Reversed' correctly returns none of these.
    SELECT 0, p_farmid, ('ADJ-' || l.adjustmentid::text)::text,
           l.transactiondate, l.transactiontype, l.amount,
           NULL::integer, NULL::text,
           NULL::text, NULL::text, NULL::text,
           NULL::text, l.description, 'Posted'::text,
           NULL::integer, NULL::integer,
           l.createdby, l.createdat,
           NULL::text, NULL::timestamp, NULL::text,
           'CashAdjustment'::text, l.adjustmentid
    FROM   fnpoultryownermoney_legacy(p_farmid) l
    WHERE  (p_type   IS NULL OR p_type = 'All' OR l.transactiontype = p_type)
      AND  (p_status IS NULL OR p_status = 'All' OR p_status = 'Posted')
      AND  (p_from IS NULL OR l.transactiondate >= p_from::timestamp)
      AND  (p_to   IS NULL OR l.transactiondate <  (p_to + 1)::timestamp)

    -- By position, because a UNION's ORDER BY cannot see either arm's column
    -- names: 4 is transactiondate, 23 is sourceid. Newest first, and stable
    -- within a date so paging cannot reshuffle rows between requests.
    ORDER  BY 4 DESC, 23 DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The cards.
--
-- Legacy rows are always live, so they join `live` unconditionally. Reversed
-- owner-money records stay excluded exactly as 253 wrote it: money that was put
-- in and taken back out is not funding.
-- -----------------------------------------------------------------------------
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
    drawcount           integer,
    -- What of the above came from the Cash / Cash Flow pages rather than from
    -- this one. Surfaced so the page can say so instead of quietly changing
    -- totals an owner has been reading for months.
    legacycount         integer,
    legacynet           numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH live AS (
        SELECT o.transactiontype, o.amount, o.transactiondate, FALSE AS islegacy
        FROM   poultryownermoney o
        WHERE  o.farmid = p_farmid AND o.status = 'Posted'
        UNION ALL
        SELECT l.transactiontype, l.amount, l.transactiondate, TRUE
        FROM   fnpoultryownermoney_legacy(p_farmid) l
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
        COUNT(*) FILTER (WHERE transactiontype = 'Draw')::int,
        COUNT(*) FILTER (WHERE islegacy)::int,
        (COALESCE(SUM(amount) FILTER (WHERE islegacy AND transactiontype = 'Contribution'), 0)
         - COALESCE(SUM(amount) FILTER (WHERE islegacy AND transactiontype = 'Draw'), 0))::numeric(14,2)
    FROM live;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
-- What the page will now show that it did not before. Read through the resolver
-- rather than the raw table so this works whichever of the two names the
-- environment uses.
SELECT 'owner adjustments now recognised' AS check,
       COALESCE(SUM(l.amount), 0)::text AS n
FROM   farms f
CROSS  JOIN LATERAL fnpoultryownermoney_legacy(f.farmid) l
WHERE  f.type = 'Poultry'

UNION ALL
-- And none of them was copied into the capital record, which is what would
-- double-count them against Cash Flow.
SELECT 'none copied into poultryownermoney',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'COPIED ' || COUNT(*) END
FROM   poultryownermoney o
WHERE  o.transactionnumber LIKE 'ADJ-%'

UNION ALL
-- The list and the cards agree about what counts. A mismatch here means the two
-- read the legacy set differently, which is exactly the bug this file exists to
-- avoid re-creating.
SELECT 'list and summary agree on the legacy count',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'DISAGREE ON ' || COUNT(*) END
FROM   farms f
CROSS  JOIN LATERAL sppoultryownermoney_summary(f.farmid, NULL, NULL) s
WHERE  f.type = 'Poultry'
  AND  s.legacycount <> (SELECT COUNT(*)::int FROM sppoultryownermoney_getall(f.farmid, NULL, NULL, NULL, NULL) g
                          WHERE g.source = 'CashAdjustment');

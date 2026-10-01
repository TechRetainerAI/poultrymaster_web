-- =============================================================================
-- 331_HotelOwnerMoneyLoansTransfersReconciliation.postgres.sql
--
-- Purpose
-- -------
-- The four Hotel MONEY items Poultry has and the Hotel did not: Owner Money,
-- Loans (Financing), Cash Transfers and Reconciliation -- plus what the Cash
-- Account page needs to match Poultry's (allow-negative flag, edit, the
-- calculated-vs-stored balance feed, Recalculate, Record Cash Adjustment).
-- HOTEL ONLY: no Poultry, Water, Generic or Restaurant object is touched.
--
-- Copied from Poultry 252 (transfers), 253 (owner money), 254 (loans) and
-- 223 (reconciliation); Restaurant 323 read as the hospitality precedent.
--
-- The rules (same as Poultry, on the Hotel's one posting path from 327)
-- ----------------------------------------------------------------------
--   * Every movement is fnhotelcash_postonce / fnhotelcash_reverse (327), which
--     go through fnhotelcash_post (325): row lock on the account, the ledger row
--     and the balance in the same statement, one row per (sourcetype, sourceid).
--   * Owner contributions / draws: FINANCING. Never revenue, never expense.
--   * Loans: the amount RECEIVED is financing in; a repayment moves cash ONCE,
--     for the total (principal + interest + fees + other) and is financing out.
--     Only interest and fees are a cost: they reach the P&L's "Depreciation &
--     Financing" band from the repayment row itself (no second cash row, no
--     expense row -- nothing to double count).
--   * Transfers: two legs (TransferOut / TransferIn). Company cash is unchanged,
--     so Cash Flow never shows them as money in or out; the summary reports
--     them as transfer volume only.
--   * Reconciliation: a count is saved as a Draft; posting measures it against
--     the LEDGER (the cached balance is healed first, as Poultry 223 does) and
--     posts the difference as one ReconciliationAdjustment row -- never an
--     expense. Record Cash Adjustment is its own document, same path.
--   * Append-only: every reversal is a new opposite ledger row with a reason.
--     Nothing posted is edited or deleted; balances are never set by hand
--     (Recalculate only rebuilds the cache from the ledger, moves no money).
--   * Cash Flow keeps telling the same story as the ledger (the 327 rule): every
--     new ledger source has an arm, and a reversal is its own row on its own day.
--
-- Order: after 327 (re-emits 327's sphotelcashflow_rows / _detail,
-- sphotelreport_pllines / _plexpensedetail and 316's sphotelcashflow_summary,
-- keeping every earlier arm). Re-run order: 325 -> 327 -> 331.
-- Idempotent: safe to run twice.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Drop the functions this file owns, by NAME (catches every overload).
-- ─────────────────────────────────────────────────────────────────────────────
DO $drop$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN (
               'fnhotelcash_assertcanpay',
               'sphotelcashaccount_update', 'sphotelcashaccount_countstatus', 'sphotelcashaccount_recalculate',
               'sphotelownermoney_record', 'sphotelownermoney_reverse', 'sphotelownermoney_list', 'sphotelownermoney_summary',
               'sphotelloan_create', 'sphotelloan_update', 'sphotelloan_cancel', 'sphotelloan_list', 'sphotelloan_summary',
               'sphotelloanpayment_record', 'sphotelloanpayment_reverse', 'sphotelloanpayment_list',
               'sphotelcashtransfer_record', 'sphotelcashtransfer_reverse', 'sphotelcashtransfer_list',
               'sphotelcashrecon_insert', 'sphotelcashrecon_update', 'sphotelcashrecon_delete',
               'sphotelcashrecon_post', 'sphotelcashrecon_reverse', 'sphotelcashrecon_list',
               'sphotelcashadjustment_record', 'sphotelcashadjustment_reverse')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema
-- ─────────────────────────────────────────────────────────────────────────────

-- Poultry's per-account overdraft rule and reconciliation stamp. Checked by the
-- functions in THIS file only (draw, repayment, transfer, adjustment), exactly
-- where Poultry checks it; 325/327 postings are unchanged. Readers of
-- hotelcashaccounts use SELECT * into a name-keyed dictionary (checked), so new
-- columns are safe.
ALTER TABLE public.hotelcashaccounts
    ADD COLUMN IF NOT EXISTS allownegativebalance  boolean NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS lastreconciledat      timestamp NULL,
    ADD COLUMN IF NOT EXISTS lastreconciledbalance numeric(14,2) NULL;

-- Owner money (Poultry 253).
CREATE TABLE IF NOT EXISTS public.hotelownermoney (
    hotelownermoneyid         serial PRIMARY KEY,
    farmid                    text NOT NULL,
    transactionnumber         text NULL,
    transactiondate           timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    transactiontype           text NOT NULL CHECK (transactiontype IN ('Contribution', 'Draw')),
    amount                    numeric(14,2) NOT NULL CHECK (amount > 0),
    hotelcashaccountid        integer NOT NULL,
    paymentmethod             text NULL,
    ownername                 text NULL,
    referencenumber           text NULL,
    notes                     text NULL,
    status                    text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    cashtransactionid         integer NULL,
    reversalcashtransactionid integer NULL,
    createdby                 text NULL,
    createdat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby                text NULL,
    reversedat                timestamp NULL,
    reversalreason            text NULL
);
CREATE INDEX IF NOT EXISTS ix_hotelownermoney_farm_date ON public.hotelownermoney (farmid, transactiondate DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelownermoney_number ON public.hotelownermoney (farmid, transactionnumber)
    WHERE transactionnumber IS NOT NULL;

-- Loans (Poultry 254).
CREATE TABLE IF NOT EXISTS public.hotelloans (
    hotelloanid               serial PRIMARY KEY,
    farmid                    text NOT NULL,
    loannumber                text NULL,
    lendername                text NOT NULL,
    lendertype                text NOT NULL DEFAULT 'Other'
                              CHECK (lendertype IN ('Bank', 'FinancialInstitution', 'Individual',
                                                    'Owner', 'FamilyFriend', 'Supplier', 'Other')),
    accountnumber             text NULL,
    loandate                  date NOT NULL,
    originalprincipal         numeric(14,2) NOT NULL CHECK (originalprincipal > 0),
    amountreceived            numeric(14,2) NOT NULL DEFAULT 0 CHECK (amountreceived >= 0),
    interestrate              numeric(9,4) NULL,
    interesttype              text NULL CHECK (interesttype IS NULL OR
                              interesttype IN ('Simple', 'ReducingBalance', 'Flat', 'Unknown')),
    termmonths                integer NULL CHECK (termmonths IS NULL OR termmonths > 0),
    paymentfrequency          text NULL CHECK (paymentfrequency IS NULL OR
                              paymentfrequency IN ('Weekly', 'BiWeekly', 'Monthly', 'Quarterly', 'Custom')),
    startdate                 date NOT NULL,
    enddate                   date NULL,
    nextpaymentdate           date NULL,
    hotelcashaccountid        integer NULL,
    outstandingprincipal      numeric(14,2) NOT NULL DEFAULT 0,
    totalprincipalrepaid      numeric(14,2) NOT NULL DEFAULT 0,
    totalinterestpaid         numeric(14,2) NOT NULL DEFAULT 0,
    totalfeespaid             numeric(14,2) NOT NULL DEFAULT 0,
    status                    text NOT NULL DEFAULT 'Active'
                              CHECK (status IN ('Draft', 'Active', 'PaidOff', 'Cancelled')),
    paidoffdate               date NULL,
    notes                     text NULL,
    cashtransactionid         integer NULL,
    reversalcashtransactionid integer NULL,
    createdby                 text NULL,
    createdat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby                 text NULL,
    updatedat                 timestamp NULL,
    reversedby                text NULL,
    reversedat                timestamp NULL,
    reversalreason            text NULL
);
CREATE INDEX IF NOT EXISTS ix_hotelloans_farm_status ON public.hotelloans (farmid, status, startdate DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelloans_number ON public.hotelloans (farmid, loannumber)
    WHERE loannumber IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.hotelloanpayments (
    hotelloanpaymentid        serial PRIMARY KEY,
    farmid                    text NOT NULL,
    hotelloanid               integer NOT NULL REFERENCES public.hotelloans (hotelloanid),
    paymentnumber             text NULL,
    paymentdate               timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    totalamount               numeric(14,2) NOT NULL CHECK (totalamount > 0),
    principalamount           numeric(14,2) NOT NULL DEFAULT 0 CHECK (principalamount >= 0),
    interestamount            numeric(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),
    feeamount                 numeric(14,2) NOT NULL DEFAULT 0 CHECK (feeamount >= 0),
    otheramount               numeric(14,2) NOT NULL DEFAULT 0 CHECK (otheramount >= 0),
    hotelcashaccountid        integer NOT NULL,
    paymentmethod             text NULL,
    referencenumber           text NULL,
    notes                     text NULL,
    status                    text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    cashtransactionid         integer NULL,
    reversalcashtransactionid integer NULL,
    createdby                 text NULL,
    createdat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby                text NULL,
    reversedat                timestamp NULL,
    reversalreason            text NULL,
    CONSTRAINT ck_hotelloanpayments_total
        CHECK (totalamount = principalamount + interestamount + feeamount + otheramount)
);
CREATE INDEX IF NOT EXISTS ix_hotelloanpayments_loan ON public.hotelloanpayments (hotelloanid, paymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_hotelloanpayments_farm ON public.hotelloanpayments (farmid, status, paymentdate DESC);

-- Transfers (Poultry 252). Always approved on record -- one request, one
-- transaction; no Draft step (Poultry's create-then-approve was two calls).
CREATE TABLE IF NOT EXISTS public.hotelcashtransfers (
    hotelcashtransferid       serial PRIMARY KEY,
    farmid                    text NOT NULL,
    transfernumber            text NULL,
    fromhotelcashaccountid    integer NOT NULL,
    tohotelcashaccountid      integer NOT NULL,
    transferdate              timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    amount                    numeric(14,2) NOT NULL CHECK (amount > 0),
    status                    text NOT NULL DEFAULT 'Approved' CHECK (status IN ('Approved', 'Reversed')),
    referencenumber           text NULL,
    notes                     text NULL,
    outgoingcashtransactionid integer NULL,
    incomingcashtransactionid integer NULL,
    reversaloutcashtransactionid integer NULL,
    reversalincashtransactionid  integer NULL,
    createdby                 text NULL,
    createdat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby                text NULL,
    reversedat                timestamp NULL,
    reversalreason            text NULL,
    CONSTRAINT ck_hotelcashtransfers_accounts CHECK (fromhotelcashaccountid <> tohotelcashaccountid)
);
CREATE INDEX IF NOT EXISTS ix_hotelcashtransfers_farm ON public.hotelcashtransfers (farmid, status, transferdate DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelcashtransfers_number ON public.hotelcashtransfers (farmid, transfernumber)
    WHERE transfernumber IS NOT NULL;

-- Reconciliation / cash counts (Poultry 223, without per-row clearing).
CREATE TABLE IF NOT EXISTS public.hotelcashreconciliations (
    hotelcashreconciliationid serial PRIMARY KEY,
    farmid                    text NOT NULL,
    hotelcashaccountid        integer NOT NULL,
    referenceno               text NULL,
    reconciliationdate        timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    systembalance             numeric(14,2) NOT NULL DEFAULT 0,
    systembalancecached       numeric(14,2) NULL,
    actualbalance             numeric(14,2) NULL,
    difference                numeric(14,2) NOT NULL DEFAULT 0,   -- actual - system
    adjustmenttransactionid   integer NULL,
    reversaltransactionid     integer NULL,
    reason                    text NULL,
    notes                     text NULL,
    status                    text NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft', 'Posted', 'Reversed')),
    createdby                 text NULL,
    createdat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat                 timestamp NULL,
    postedby                  text NULL,
    postedat                  timestamp NULL,
    reversedby                text NULL,
    reversedat                timestamp NULL,
    reversalreason            text NULL
);
CREATE INDEX IF NOT EXISTS ix_hotelcashrecon_farm_account
    ON public.hotelcashreconciliations (farmid, hotelcashaccountid, reconciliationdate DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelcashrecon_one_draft
    ON public.hotelcashreconciliations (farmid, hotelcashaccountid) WHERE status = 'Draft';
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelcashrecon_ref
    ON public.hotelcashreconciliations (farmid, referenceno) WHERE referenceno IS NOT NULL;

-- Record Cash Adjustment (Poultry's adjust, as its own document so the ledger
-- row has a source and can be reversed).
CREATE TABLE IF NOT EXISTS public.hotelcashadjustments (
    hotelcashadjustmentid     serial PRIMARY KEY,
    farmid                    text NOT NULL,
    hotelcashaccountid        integer NOT NULL,
    adjustmentnumber          text NULL,
    adjustmentdate            timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    amount                    numeric(14,2) NOT NULL CHECK (amount <> 0),   -- SIGNED: + in, - out
    reason                    text NOT NULL,
    status                    text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    cashtransactionid         integer NULL,
    reversalcashtransactionid integer NULL,
    createdby                 text NULL,
    createdat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby                text NULL,
    reversedat                timestamp NULL,
    reversalreason            text NULL
);
CREATE INDEX IF NOT EXISTS ix_hotelcashadjustments_farm ON public.hotelcashadjustments (farmid, hotelcashaccountid, adjustmentdate DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Guard: can this account pay this much? (Poultry's allownegativebalance)
--    Locks the account row first so two payments cannot both pass the check.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelcash_assertcanpay(
    p_farmid    text,
    p_accountid integer,
    p_amount    numeric,
    p_message   text
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_bal numeric; v_neg boolean; v_active boolean;
BEGIN
    SELECT a.currentbalance, a.allownegativebalance, a.isactive INTO v_bal, v_neg, v_active
    FROM   public.hotelcashaccounts a
    WHERE  a.hotelcashaccountid = p_accountid AND a.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That cash account does not belong to this hotel.';
    END IF;
    IF NOT v_neg AND (v_bal - p_amount) < 0 THEN
        RAISE EXCEPTION '%', p_message;
    END IF;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Cash accounts: edit, calculated-vs-stored feed, Recalculate
-- ─────────────────────────────────────────────────────────────────────────────

-- The descriptive fields only. Opening and current balance are never edited
-- here: the opening is fixed at creation, the current is the ledger's.
CREATE FUNCTION public.sphotelcashaccount_update(
    p_farmid               text,
    p_accountid            integer,
    p_accountname          text,
    p_accounttype          text,
    p_allownegativebalance boolean,
    p_isactive             boolean,
    p_notes                text,
    p_purpose              text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF COALESCE(btrim(p_accountname), '') = '' THEN
        RAISE EXCEPTION 'Name required';
    END IF;
    PERFORM 1 FROM public.hotelcashaccounts a
    WHERE a.hotelcashaccountid = p_accountid AND a.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That cash account does not belong to this hotel.';
    END IF;
    -- One account per purpose (the rule the purpose endpoint already keeps).
    IF NULLIF(btrim(p_purpose), '') IS NOT NULL THEN
        UPDATE public.hotelcashaccounts SET purpose = NULL, updatedat = now()
        WHERE  farmid = p_farmid AND purpose = btrim(p_purpose) AND hotelcashaccountid <> p_accountid;
    END IF;
    UPDATE public.hotelcashaccounts a
    SET    accountname          = btrim(p_accountname),
           accounttype          = COALESCE(NULLIF(btrim(p_accounttype), ''), a.accounttype),
           allownegativebalance = COALESCE(p_allownegativebalance, a.allownegativebalance),
           isactive             = COALESCE(p_isactive, a.isactive),
           notes                = NULLIF(btrim(p_notes), ''),
           purpose              = NULLIF(btrim(p_purpose), ''),
           updatedat            = now()
    WHERE  a.hotelcashaccountid = p_accountid AND a.farmid = p_farmid;
END;
$function$;

-- Per account: stored balance, what the ledger says, the drift between them and
-- when it was last reconciled (Poultry 223's count-status feed). "Uncleared" is
-- derived -- ledger rows dated after the last posted reconciliation -- because
-- the Hotel ledger has no per-row clearing column.
CREATE FUNCTION public.sphotelcashaccount_countstatus(p_farmid text)
RETURNS TABLE(
    hotelcashaccountid    integer,
    accountname           text,
    accounttype           text,
    isactive              boolean,
    currentbalance        numeric,
    ledgerbalance         numeric,
    cachedrift            numeric,
    lastreconciledat      timestamp,
    lastreconciledbalance numeric,
    dayssincereconciled   integer,
    unclearedcount        integer,
    unclearedamount       numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT a.hotelcashaccountid, a.accountname::text, a.accounttype::text, a.isactive,
           a.currentbalance,
           l.ledger,
           ROUND(a.currentbalance - l.ledger, 2),
           a.lastreconciledat, a.lastreconciledbalance,
           CASE WHEN a.lastreconciledat IS NULL THEN NULL
                ELSE (CURRENT_DATE - a.lastreconciledat::date)::integer END,
           u.n, u.amt
    FROM   public.hotelcashaccounts a
    CROSS  JOIN LATERAL (
        SELECT ROUND(a.openingbalance + COALESCE(SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END), 0), 2) AS ledger
        FROM   public.hotelcashtransactions t
        WHERE  t.hotelcashaccountid = a.hotelcashaccountid AND t.farmid = a.farmid
    ) l
    CROSS  JOIN LATERAL (
        SELECT COUNT(*)::integer AS n,
               COALESCE(SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END), 0)::numeric AS amt
        FROM   public.hotelcashtransactions t
        WHERE  t.hotelcashaccountid = a.hotelcashaccountid AND t.farmid = a.farmid
          AND  (a.lastreconciledat IS NULL OR t.txndate::timestamp > a.lastreconciledat)
          AND  t.sourcetype NOT IN ('ReconciliationAdjustment')
    ) u
    WHERE  a.farmid = p_farmid
    ORDER  BY a.accountname;
$function$;

-- Recalculate: rebuild every stored balance from opening + ledger. Moves no
-- money and writes no ledger row. Returns how many accounts changed.
CREATE FUNCTION public.sphotelcashaccount_recalculate(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE v_n integer;
BEGIN
    WITH truth AS (
        SELECT a.hotelcashaccountid AS id,
               ROUND(a.openingbalance + COALESCE((
                   SELECT SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)
                   FROM   public.hotelcashtransactions t
                   WHERE  t.hotelcashaccountid = a.hotelcashaccountid AND t.farmid = a.farmid), 0), 2) AS bal
        FROM   public.hotelcashaccounts a
        WHERE  a.farmid = p_farmid
        FOR UPDATE OF a
    )
    UPDATE public.hotelcashaccounts a
    SET    currentbalance = t.bal, updatedat = now()
    FROM   truth t
    WHERE  a.hotelcashaccountid = t.id AND a.currentbalance IS DISTINCT FROM t.bal;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Owner money (Poultry 253)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelownermoney_record(
    p_farmid          text,
    p_transactiontype text,
    p_amount          numeric,
    p_accountid       integer,
    p_transactiondate timestamp DEFAULT NULL,
    p_paymentmethod   text DEFAULT NULL,
    p_ownername       text DEFAULT NULL,
    p_referencenumber text DEFAULT NULL,
    p_notes           text DEFAULT NULL,
    p_createdby       text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_date timestamp := COALESCE(p_transactiondate, (now() at time zone 'utc'));
    v_txn  integer;
BEGIN
    IF COALESCE(p_transactiontype, '') NOT IN ('Contribution', 'Draw') THEN
        RAISE EXCEPTION 'Owner money must be a Contribution or a Draw (got "%").', p_transactiontype;
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Owner money amount must be greater than zero.';
    END IF;
    IF p_accountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money moves through.';
    END IF;
    -- A draw takes money out and can overdraw; a contribution never can.
    IF p_transactiontype = 'Draw' THEN
        PERFORM public.fnhotelcash_assertcanpay(p_farmid, p_accountid, p_amount,
                                                'This draw would take the cash account below zero.');
    END IF;

    INSERT INTO public.hotelownermoney (
        farmid, transactiondate, transactiontype, amount, hotelcashaccountid,
        paymentmethod, ownername, referencenumber, notes, status, createdby)
    VALUES (
        p_farmid, v_date, p_transactiontype, p_amount, p_accountid,
        NULLIF(btrim(p_paymentmethod), ''), NULLIF(btrim(p_ownername), ''),
        NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_notes), ''), 'Posted', p_createdby)
    RETURNING hotelownermoneyid INTO v_id;

    UPDATE public.hotelownermoney
    SET    transactionnumber = CASE WHEN p_transactiontype = 'Contribution' THEN 'OWN-' ELSE 'OWD-' END
                               || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  hotelownermoneyid = v_id;

    -- THE one cash row. Not a sale, not an expense, not a payment.
    v_txn := public.fnhotelcash_postonce(
        p_farmid, p_accountid,
        CASE WHEN p_transactiontype = 'Contribution' THEN 'Credit' ELSE 'Debit' END,
        p_amount,
        COALESCE(NULLIF(btrim(p_notes), ''),
                 CASE WHEN p_transactiontype = 'Contribution' THEN 'Owner contribution' ELSE 'Owner draw' END),
        NULLIF(btrim(p_referencenumber), ''),
        'OwnerMoney', v_id, p_createdby, v_date);

    UPDATE public.hotelownermoney SET cashtransactionid = v_txn WHERE hotelownermoneyid = v_id;
    RETURN v_id;
END;
$function$;

CREATE FUNCTION public.sphotelownermoney_reverse(
    p_farmid     text,
    p_id         integer,
    p_reason     text,
    p_reversedby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v record; v_txn integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse owner money.';
    END IF;
    SELECT * INTO v FROM public.hotelownermoney o
    WHERE  o.hotelownermoneyid = p_id AND o.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Owner money record % not found.', p_id;
    END IF;
    IF v.status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted owner money record can be reversed (this one is %).', v.status;
    END IF;
    -- Undoing a contribution moves money OUT again.
    IF v.transactiontype = 'Contribution' THEN
        PERFORM public.fnhotelcash_assertcanpay(p_farmid, v.hotelcashaccountid, v.amount,
            'The cash account no longer holds this contribution; reversing it would overdraw the account.');
    END IF;
    v_txn := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'OwnerMoneyReversal', p_reason, p_reversedby);
    UPDATE public.hotelownermoney
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = (now() at time zone 'utc'),
           reversalreason = btrim(p_reason), reversalcashtransactionid = v_txn
    WHERE  hotelownermoneyid = p_id;
END;
$function$;

CREATE FUNCTION public.sphotelownermoney_list(
    p_farmid text,
    p_type   text DEFAULT NULL,
    p_from   date DEFAULT NULL,
    p_to     date DEFAULT NULL,
    p_status text DEFAULT NULL
) RETURNS TABLE(
    hotelownermoneyid integer, transactionnumber text, transactiondate timestamp, transactiontype text,
    amount numeric, hotelcashaccountid integer, accountname text, paymentmethod text, ownername text,
    referencenumber text, notes text, status text, createdby text, createdat timestamp,
    reversedby text, reversedat timestamp, reversalreason text
)
LANGUAGE sql STABLE
AS $function$
    SELECT o.hotelownermoneyid, o.transactionnumber, o.transactiondate, o.transactiontype,
           o.amount, o.hotelcashaccountid, a.accountname::text, o.paymentmethod, o.ownername,
           o.referencenumber, o.notes, o.status, o.createdby, o.createdat,
           o.reversedby, o.reversedat, o.reversalreason
    FROM   public.hotelownermoney o
    LEFT   JOIN public.hotelcashaccounts a ON a.hotelcashaccountid = o.hotelcashaccountid
    WHERE  o.farmid = p_farmid
      AND  (p_type   IS NULL OR p_type = 'All'   OR o.transactiontype = p_type)
      AND  (p_status IS NULL OR p_status = 'All' OR o.status = p_status)
      AND  (p_from IS NULL OR o.transactiondate >= p_from::timestamp)
      AND  (p_to   IS NULL OR o.transactiondate <  (p_to + 1)::timestamp)
    ORDER  BY o.transactiondate DESC, o.hotelownermoneyid DESC;
$function$;

-- The five cards. Reversed records are excluded from every total.
CREATE FUNCTION public.sphotelownermoney_summary(
    p_farmid text,
    p_from   date DEFAULT NULL,
    p_to     date DEFAULT NULL
) RETURNS TABLE(
    totalcontributions numeric, totaldraws numeric, netfunding numeric,
    periodcontributions numeric, perioddraws numeric,
    contributioncount integer, drawcount integer
)
LANGUAGE sql STABLE
AS $function$
    WITH live AS (
        SELECT o.transactiontype, o.amount, o.transactiondate
        FROM   public.hotelownermoney o
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
        (COUNT(*) FILTER (WHERE transactiontype = 'Contribution'))::integer,
        (COUNT(*) FILTER (WHERE transactiontype = 'Draw'))::integer
    FROM live;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Loans (Poultry 254)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelloan_create(
    p_farmid            text,
    p_lendername        text,
    p_originalprincipal numeric,
    p_startdate         date,
    p_amountreceived    numeric DEFAULT 0,
    p_accountid         integer DEFAULT NULL,
    p_lendertype        text DEFAULT 'Other',
    p_accountnumber     text DEFAULT NULL,
    p_loandate          date DEFAULT NULL,
    p_interestrate      numeric DEFAULT NULL,
    p_interesttype      text DEFAULT NULL,
    p_termmonths        integer DEFAULT NULL,
    p_paymentfrequency  text DEFAULT NULL,
    p_enddate           date DEFAULT NULL,
    p_nextpaymentdate   date DEFAULT NULL,
    p_notes             text DEFAULT NULL,
    p_createdby         text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_date date := COALESCE(p_loandate, p_startdate);
    v_txn  integer;
BEGIN
    IF COALESCE(btrim(p_lendername), '') = '' THEN
        RAISE EXCEPTION 'A lender is required.';
    END IF;
    IF COALESCE(p_originalprincipal, 0) <= 0 THEN
        RAISE EXCEPTION 'The loan principal must be greater than zero.';
    END IF;
    IF p_startdate IS NULL THEN
        RAISE EXCEPTION 'A start date is required.';
    END IF;
    IF COALESCE(p_amountreceived, 0) < 0 THEN
        RAISE EXCEPTION 'The amount received cannot be negative.';
    END IF;
    IF COALESCE(p_amountreceived, 0) > p_originalprincipal THEN
        RAISE EXCEPTION 'The amount received (%) cannot exceed the principal (%).',
            p_amountreceived, p_originalprincipal;
    END IF;
    IF COALESCE(p_amountreceived, 0) > 0 AND p_accountid IS NULL THEN
        RAISE EXCEPTION 'Say which cash account received the money.';
    END IF;

    INSERT INTO public.hotelloans (
        farmid, lendername, lendertype, accountnumber, loandate,
        originalprincipal, amountreceived, interestrate, interesttype, termmonths,
        paymentfrequency, startdate, enddate, nextpaymentdate, hotelcashaccountid,
        outstandingprincipal, status, notes, createdby)
    VALUES (
        p_farmid, btrim(p_lendername), COALESCE(p_lendertype, 'Other'),
        NULLIF(btrim(p_accountnumber), ''), v_date,
        p_originalprincipal, COALESCE(p_amountreceived, 0),
        p_interestrate, p_interesttype, p_termmonths,
        p_paymentfrequency, p_startdate, p_enddate, p_nextpaymentdate,
        CASE WHEN COALESCE(p_amountreceived, 0) > 0 THEN p_accountid END,
        -- The debt starts at what is OWED, not at what arrived.
        p_originalprincipal, 'Active', NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING hotelloanid INTO v_id;

    UPDATE public.hotelloans
    SET    loannumber = 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  hotelloanid = v_id;

    -- The disbursement. ONE cash row, and only if the money actually arrived.
    IF COALESCE(p_amountreceived, 0) > 0 THEN
        v_txn := public.fnhotelcash_postonce(
            p_farmid, p_accountid, 'Credit', p_amountreceived,
            'Loan received from ' || btrim(p_lendername), NULLIF(btrim(p_accountnumber), ''),
            'LoanReceived', v_id, p_createdby, v_date::timestamp);
        UPDATE public.hotelloans SET cashtransactionid = v_txn WHERE hotelloanid = v_id;
    END IF;
    RETURN v_id;
END;
$function$;

-- Descriptive fields only; principal, received and the running totals are
-- consequences of postings and cannot be typed over.
CREATE FUNCTION public.sphotelloan_update(
    p_farmid           text,
    p_loanid           integer,
    p_lendername       text DEFAULT NULL,
    p_lendertype       text DEFAULT NULL,
    p_accountnumber    text DEFAULT NULL,
    p_interestrate     numeric DEFAULT NULL,
    p_interesttype     text DEFAULT NULL,
    p_termmonths       integer DEFAULT NULL,
    p_paymentfrequency text DEFAULT NULL,
    p_enddate          date DEFAULT NULL,
    p_nextpaymentdate  date DEFAULT NULL,
    p_notes            text DEFAULT NULL,
    p_updatedby        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_status text;
BEGIN
    SELECT l.status INTO v_status FROM public.hotelloans l
    WHERE  l.hotelloanid = p_loanid AND l.farmid = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_loanid; END IF;
    IF v_status = 'Cancelled' THEN RAISE EXCEPTION 'A % loan cannot be edited.', v_status; END IF;
    UPDATE public.hotelloans l
    SET    lendername       = COALESCE(NULLIF(btrim(p_lendername), ''), l.lendername),
           lendertype       = COALESCE(p_lendertype, l.lendertype),
           accountnumber    = COALESCE(NULLIF(btrim(p_accountnumber), ''), l.accountnumber),
           interestrate     = COALESCE(p_interestrate, l.interestrate),
           interesttype     = COALESCE(p_interesttype, l.interesttype),
           termmonths       = COALESCE(p_termmonths, l.termmonths),
           paymentfrequency = COALESCE(p_paymentfrequency, l.paymentfrequency),
           enddate          = COALESCE(p_enddate, l.enddate),
           nextpaymentdate  = COALESCE(p_nextpaymentdate, l.nextpaymentdate),
           notes            = COALESCE(NULLIF(btrim(p_notes), ''), l.notes),
           updatedby        = p_updatedby,
           updatedat        = (now() at time zone 'utc')
    WHERE  l.hotelloanid = p_loanid AND l.farmid = p_farmid;
END;
$function$;

-- Cancel a loan that never happened: only while nothing is repaid. Money that
-- arrived goes back out by an opposite row.
CREATE FUNCTION public.sphotelloan_cancel(
    p_farmid      text,
    p_loanid      integer,
    p_reason      text,
    p_cancelledby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v record; v_paid integer; v_txn integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to cancel a loan.';
    END IF;
    SELECT * INTO v FROM public.hotelloans l
    WHERE  l.hotelloanid = p_loanid AND l.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan % not found.', p_loanid; END IF;
    IF v.status = 'Cancelled' THEN RAISE EXCEPTION 'This loan is already %.', v.status; END IF;
    SELECT COUNT(*) INTO v_paid FROM public.hotelloanpayments p
    WHERE  p.hotelloanid = p_loanid AND p.status = 'Posted';
    IF v_paid > 0 THEN
        RAISE EXCEPTION 'This loan has % posted repayment(s); reverse them before cancelling it.', v_paid;
    END IF;
    IF v.cashtransactionid IS NOT NULL THEN
        v_txn := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'LoanReceivedReversal', p_reason, p_cancelledby);
    END IF;
    UPDATE public.hotelloans
    SET    status = 'Cancelled', outstandingprincipal = 0,
           reversalcashtransactionid = v_txn,
           reversedby = p_cancelledby, reversedat = (now() at time zone 'utc'),
           reversalreason = btrim(p_reason), updatedat = (now() at time zone 'utc')
    WHERE  hotelloanid = p_loanid;
END;
$function$;

-- Record a repayment: one payment row, the loan's running totals, and ONE cash
-- row for the TOTAL. Interest and fees are read by the P&L from this row.
CREATE FUNCTION public.sphotelloanpayment_record(
    p_farmid          text,
    p_loanid          integer,
    p_accountid       integer,
    p_principalamount numeric DEFAULT 0,
    p_interestamount  numeric DEFAULT 0,
    p_feeamount       numeric DEFAULT 0,
    p_otheramount     numeric DEFAULT 0,
    p_paymentdate     timestamp DEFAULT NULL,
    p_paymentmethod   text DEFAULT NULL,
    p_referencenumber text DEFAULT NULL,
    p_notes           text DEFAULT NULL,
    p_nextpaymentdate date DEFAULT NULL,
    p_createdby       text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id        integer;
    v_date      timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_principal numeric := COALESCE(p_principalamount, 0);
    v_interest  numeric := COALESCE(p_interestamount, 0);
    v_fee       numeric := COALESCE(p_feeamount, 0);
    v_other     numeric := COALESCE(p_otheramount, 0);
    v_total     numeric;
    v           record;
    v_txn       integer;
    v_newout    numeric;
BEGIN
    v_total := v_principal + v_interest + v_fee + v_other;
    IF v_principal < 0 OR v_interest < 0 OR v_fee < 0 OR v_other < 0 THEN
        RAISE EXCEPTION 'No part of a repayment can be negative.';
    END IF;
    IF v_total <= 0 THEN
        RAISE EXCEPTION 'A repayment must be greater than zero.';
    END IF;
    IF p_accountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money moves through.';
    END IF;
    SELECT * INTO v FROM public.hotelloans l
    WHERE  l.hotelloanid = p_loanid AND l.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan % not found.', p_loanid; END IF;
    IF v.status = 'Cancelled' THEN RAISE EXCEPTION 'A % loan cannot be repaid.', v.status; END IF;
    IF v.status = 'Draft' THEN RAISE EXCEPTION 'Activate the loan before recording repayments against it.'; END IF;
    IF v_principal > v.outstandingprincipal THEN
        RAISE EXCEPTION 'Principal of % is more than the % still outstanding.', v_principal, v.outstandingprincipal;
    END IF;
    PERFORM public.fnhotelcash_assertcanpay(p_farmid, p_accountid, v_total,
                                            'This repayment would take the cash account below zero.');

    INSERT INTO public.hotelloanpayments (
        farmid, hotelloanid, paymentdate, totalamount,
        principalamount, interestamount, feeamount, otheramount,
        hotelcashaccountid, paymentmethod, referencenumber, notes, status, createdby)
    VALUES (
        p_farmid, p_loanid, v_date, v_total, v_principal, v_interest, v_fee, v_other,
        p_accountid, NULLIF(btrim(p_paymentmethod), ''), NULLIF(btrim(p_referencenumber), ''),
        NULLIF(btrim(p_notes), ''), 'Posted', p_createdby)
    RETURNING hotelloanpaymentid INTO v_id;

    UPDATE public.hotelloanpayments
    SET    paymentnumber = 'LP-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  hotelloanpaymentid = v_id;

    -- ONE cash row, for the TOTAL.
    v_txn := public.fnhotelcash_postonce(
        p_farmid, p_accountid, 'Debit', v_total,
        'Loan repayment to ' || COALESCE(v.lendername, 'lender'),
        NULLIF(btrim(p_referencenumber), ''), 'LoanPayment', v_id, p_createdby, v_date);
    UPDATE public.hotelloanpayments SET cashtransactionid = v_txn WHERE hotelloanpaymentid = v_id;

    v_newout := v.outstandingprincipal - v_principal;
    UPDATE public.hotelloans l
    SET    outstandingprincipal = v_newout,
           totalprincipalrepaid = l.totalprincipalrepaid + v_principal,
           totalinterestpaid    = l.totalinterestpaid + v_interest,
           totalfeespaid        = l.totalfeespaid + v_fee,
           nextpaymentdate      = COALESCE(p_nextpaymentdate, l.nextpaymentdate),
           status      = CASE WHEN v_newout <= 0 THEN 'PaidOff' ELSE 'Active' END,
           paidoffdate = CASE WHEN v_newout <= 0 THEN v_date::date ELSE NULL END,
           updatedat   = (now() at time zone 'utc')
    WHERE  l.hotelloanid = p_loanid;
    RETURN v_id;
END;
$function$;

CREATE FUNCTION public.sphotelloanpayment_reverse(
    p_farmid     text,
    p_paymentid  integer,
    p_reason     text,
    p_reversedby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v record; v_txn integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a repayment.';
    END IF;
    SELECT * INTO v FROM public.hotelloanpayments p
    WHERE  p.hotelloanpaymentid = p_paymentid AND p.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan payment % not found.', p_paymentid; END IF;
    IF v.status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted repayment can be reversed (this one is %).', v.status;
    END IF;
    PERFORM 1 FROM public.hotelloans l WHERE l.hotelloanid = v.hotelloanid FOR UPDATE;

    -- The money comes back into the account it left.
    v_txn := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'LoanPaymentReversal', p_reason, p_reversedby);

    -- The debt goes back up, and a loan that was paid off is live again.
    UPDATE public.hotelloans l
    SET    outstandingprincipal = l.outstandingprincipal + v.principalamount,
           totalprincipalrepaid = GREATEST(l.totalprincipalrepaid - v.principalamount, 0),
           totalinterestpaid    = GREATEST(l.totalinterestpaid - v.interestamount, 0),
           totalfeespaid        = GREATEST(l.totalfeespaid - v.feeamount, 0),
           status = CASE WHEN l.status = 'PaidOff' AND (l.outstandingprincipal + v.principalamount) > 0
                         THEN 'Active' ELSE l.status END,
           paidoffdate = CASE WHEN (l.outstandingprincipal + v.principalamount) > 0 THEN NULL ELSE l.paidoffdate END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.hotelloanid = v.hotelloanid;

    UPDATE public.hotelloanpayments
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = (now() at time zone 'utc'),
           reversalreason = btrim(p_reason), reversalcashtransactionid = v_txn
    WHERE  hotelloanpaymentid = p_paymentid;
END;
$function$;

-- Overdue is DERIVED, never stored (Poultry 254).
CREATE FUNCTION public.sphotelloan_list(p_farmid text, p_status text DEFAULT NULL)
RETURNS TABLE(
    hotelloanid integer, loannumber text, lendername text, lendertype text, accountnumber text,
    loandate date, originalprincipal numeric, amountreceived numeric, interestrate numeric,
    interesttype text, termmonths integer, paymentfrequency text, startdate date, enddate date,
    nextpaymentdate date, hotelcashaccountid integer, accountname text, outstandingprincipal numeric,
    totalprincipalrepaid numeric, totalinterestpaid numeric, totalfeespaid numeric, status text,
    isoverdue boolean, paymentcount integer, paidoffdate date, notes text, createdby text,
    createdat timestamp, reversalreason text
)
LANGUAGE sql STABLE
AS $function$
    SELECT l.hotelloanid, l.loannumber, l.lendername, l.lendertype, l.accountnumber,
           l.loandate, l.originalprincipal, l.amountreceived, l.interestrate,
           l.interesttype, l.termmonths, l.paymentfrequency, l.startdate, l.enddate,
           l.nextpaymentdate, l.hotelcashaccountid, a.accountname::text, l.outstandingprincipal,
           l.totalprincipalrepaid, l.totalinterestpaid, l.totalfeespaid, l.status,
           (l.status = 'Active' AND l.nextpaymentdate IS NOT NULL
            AND l.nextpaymentdate < CURRENT_DATE AND l.outstandingprincipal > 0),
           (SELECT COUNT(*)::integer FROM public.hotelloanpayments p
             WHERE p.hotelloanid = l.hotelloanid AND p.status = 'Posted'),
           l.paidoffdate, l.notes, l.createdby, l.createdat, l.reversalreason
    FROM   public.hotelloans l
    LEFT   JOIN public.hotelcashaccounts a ON a.hotelcashaccountid = l.hotelcashaccountid
    WHERE  l.farmid = p_farmid
      AND  (p_status IS NULL OR p_status = 'All' OR l.status = p_status)
    ORDER  BY l.startdate DESC, l.hotelloanid DESC;
$function$;

CREATE FUNCTION public.sphotelloanpayment_list(p_farmid text, p_loanid integer DEFAULT NULL)
RETURNS TABLE(
    hotelloanpaymentid integer, hotelloanid integer, loannumber text, lendername text,
    paymentnumber text, paymentdate timestamp, totalamount numeric, principalamount numeric,
    interestamount numeric, feeamount numeric, otheramount numeric, hotelcashaccountid integer,
    accountname text, paymentmethod text, referencenumber text, notes text, status text,
    createdby text, createdat timestamp, reversedby text, reversedat timestamp, reversalreason text
)
LANGUAGE sql STABLE
AS $function$
    SELECT p.hotelloanpaymentid, p.hotelloanid, l.loannumber, l.lendername,
           p.paymentnumber, p.paymentdate, p.totalamount, p.principalamount,
           p.interestamount, p.feeamount, p.otheramount, p.hotelcashaccountid,
           a.accountname::text, p.paymentmethod, p.referencenumber, p.notes, p.status,
           p.createdby, p.createdat, p.reversedby, p.reversedat, p.reversalreason
    FROM   public.hotelloanpayments p
    JOIN   public.hotelloans l ON l.hotelloanid = p.hotelloanid
    LEFT   JOIN public.hotelcashaccounts a ON a.hotelcashaccountid = p.hotelcashaccountid
    WHERE  p.farmid = p_farmid
      AND  (p_loanid IS NULL OR p.hotelloanid = p_loanid)
    ORDER  BY p.paymentdate DESC, p.hotelloanpaymentid DESC;
$function$;

CREATE FUNCTION public.sphotelloan_summary(p_farmid text)
RETURNS TABLE(
    activeloans integer, totalborrowed numeric, totalreceived numeric, outstandingprincipal numeric,
    totalprincipalrepaid numeric, totalinterestpaid numeric, totalfeespaid numeric,
    overdueloans integer, nextpaymentdate date
)
LANGUAGE sql STABLE
AS $function$
    SELECT
        (COUNT(*) FILTER (WHERE l.status = 'Active'))::integer,
        COALESCE(SUM(l.originalprincipal) FILTER (WHERE l.status <> 'Cancelled'), 0)::numeric(14,2),
        COALESCE(SUM(l.amountreceived)    FILTER (WHERE l.status <> 'Cancelled'), 0)::numeric(14,2),
        COALESCE(SUM(l.outstandingprincipal), 0)::numeric(14,2),
        COALESCE(SUM(l.totalprincipalrepaid), 0)::numeric(14,2),
        COALESCE(SUM(l.totalinterestpaid), 0)::numeric(14,2),
        COALESCE(SUM(l.totalfeespaid), 0)::numeric(14,2),
        (COUNT(*) FILTER (WHERE l.status = 'Active' AND l.nextpaymentdate IS NOT NULL
                            AND l.nextpaymentdate < CURRENT_DATE AND l.outstandingprincipal > 0))::integer,
        MIN(l.nextpaymentdate) FILTER (WHERE l.status = 'Active' AND l.outstandingprincipal > 0)
    FROM public.hotelloans l
    WHERE l.farmid = p_farmid;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Cash transfers (Poultry 252) -- two legs, one transaction
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelcashtransfer_record(
    p_farmid          text,
    p_fromaccountid   integer,
    p_toaccountid     integer,
    p_amount          numeric,
    p_transferdate    timestamp DEFAULT NULL,
    p_referencenumber text DEFAULT NULL,
    p_notes           text DEFAULT NULL,
    p_createdby       text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_date timestamp := COALESCE(p_transferdate, (now() at time zone 'utc'));
    v_from text; v_to text;
    v_out  integer; v_in integer;
BEGIN
    IF p_fromaccountid IS NULL OR p_toaccountid IS NULL THEN
        RAISE EXCEPTION 'Pick both accounts';
    END IF;
    IF p_fromaccountid = p_toaccountid THEN
        RAISE EXCEPTION 'Cash transfer cannot be to the same account.';
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be greater than zero.';
    END IF;
    SELECT a.accountname INTO v_from FROM public.hotelcashaccounts a
    WHERE a.hotelcashaccountid = p_fromaccountid AND a.farmid = p_farmid;
    IF v_from IS NULL THEN RAISE EXCEPTION 'Source cash account does not belong to this hotel.'; END IF;
    SELECT a.accountname INTO v_to FROM public.hotelcashaccounts a
    WHERE a.hotelcashaccountid = p_toaccountid AND a.farmid = p_farmid;
    IF v_to IS NULL THEN RAISE EXCEPTION 'Destination cash account does not belong to this hotel.'; END IF;

    -- Lock both accounts in id order so two opposite transfers cannot deadlock.
    PERFORM 1 FROM public.hotelcashaccounts a
    WHERE a.hotelcashaccountid IN (p_fromaccountid, p_toaccountid)
    ORDER BY a.hotelcashaccountid FOR UPDATE;
    PERFORM public.fnhotelcash_assertcanpay(p_farmid, p_fromaccountid, p_amount,
                                            'Source cash account would go negative; transfer rejected.');

    INSERT INTO public.hotelcashtransfers (
        farmid, fromhotelcashaccountid, tohotelcashaccountid, transferdate, amount,
        status, referencenumber, notes, createdby)
    VALUES (
        p_farmid, p_fromaccountid, p_toaccountid, v_date, p_amount,
        'Approved', NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING hotelcashtransferid INTO v_id;
    UPDATE public.hotelcashtransfers
    SET    transfernumber = 'TRF-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  hotelcashtransferid = v_id;

    v_out := public.fnhotelcash_postonce(p_farmid, p_fromaccountid, 'Debit', p_amount,
                 'Transfer out to ' || v_to || COALESCE(' - ' || NULLIF(btrim(p_notes), ''), ''),
                 NULLIF(btrim(p_referencenumber), ''), 'TransferOut', v_id, p_createdby, v_date);
    v_in  := public.fnhotelcash_postonce(p_farmid, p_toaccountid, 'Credit', p_amount,
                 'Transfer in from ' || v_from || COALESCE(' - ' || NULLIF(btrim(p_notes), ''), ''),
                 NULLIF(btrim(p_referencenumber), ''), 'TransferIn', v_id, p_createdby, v_date);
    UPDATE public.hotelcashtransfers
    SET    outgoingcashtransactionid = v_out, incomingcashtransactionid = v_in
    WHERE  hotelcashtransferid = v_id;
    RETURN v_id;
END;
$function$;

-- Two more rows in the opposite direction. The guard flips: the money comes
-- back OUT of the destination, so that is the account that must afford it.
CREATE FUNCTION public.sphotelcashtransfer_reverse(
    p_farmid     text,
    p_transferid integer,
    p_reason     text,
    p_reversedby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v record; v_a integer; v_b integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cash transfer.';
    END IF;
    SELECT * INTO v FROM public.hotelcashtransfers t
    WHERE  t.hotelcashtransferid = p_transferid AND t.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash transfer % not found.', p_transferid; END IF;
    IF v.status <> 'Approved' THEN
        RAISE EXCEPTION 'Only an approved transfer can be reversed (this one is %).', v.status;
    END IF;
    PERFORM 1 FROM public.hotelcashaccounts a
    WHERE a.hotelcashaccountid IN (v.fromhotelcashaccountid, v.tohotelcashaccountid)
    ORDER BY a.hotelcashaccountid FOR UPDATE;
    PERFORM public.fnhotelcash_assertcanpay(p_farmid, v.tohotelcashaccountid, v.amount,
        'The destination account no longer holds this money; reversing the transfer would overdraw it.');

    v_a := public.fnhotelcash_reverse(p_farmid, v.incomingcashtransactionid, 'TransferReversalOut', p_reason, p_reversedby);
    v_b := public.fnhotelcash_reverse(p_farmid, v.outgoingcashtransactionid, 'TransferReversalIn',  p_reason, p_reversedby);
    UPDATE public.hotelcashtransfers
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = (now() at time zone 'utc'),
           reversalreason = btrim(p_reason),
           reversaloutcashtransactionid = v_a, reversalincashtransactionid = v_b
    WHERE  hotelcashtransferid = p_transferid;
END;
$function$;

CREATE FUNCTION public.sphotelcashtransfer_list(p_farmid text)
RETURNS TABLE(
    hotelcashtransferid integer, transfernumber text, fromhotelcashaccountid integer, fromaccountname text,
    tohotelcashaccountid integer, toaccountname text, transferdate timestamp, amount numeric, status text,
    referencenumber text, notes text, createdby text, createdat timestamp,
    reversedby text, reversedat timestamp, reversalreason text
)
LANGUAGE sql STABLE
AS $function$
    SELECT t.hotelcashtransferid, t.transfernumber, t.fromhotelcashaccountid, fa.accountname::text,
           t.tohotelcashaccountid, ta.accountname::text, t.transferdate, t.amount, t.status,
           t.referencenumber, t.notes, t.createdby, t.createdat,
           t.reversedby, t.reversedat, t.reversalreason
    FROM   public.hotelcashtransfers t
    LEFT   JOIN public.hotelcashaccounts fa ON fa.hotelcashaccountid = t.fromhotelcashaccountid
    LEFT   JOIN public.hotelcashaccounts ta ON ta.hotelcashaccountid = t.tohotelcashaccountid
    WHERE  t.farmid = p_farmid
    ORDER  BY t.transferdate DESC, t.hotelcashtransferid DESC;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Reconciliation (Poultry 223): Draft -> Post -> (Reverse)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelcashrecon_insert(
    p_farmid             text,
    p_accountid          integer,
    p_reconciliationdate timestamp DEFAULT NULL,
    p_actualbalance      numeric DEFAULT NULL,
    p_reason             text DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_createdby          text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE v_open integer; v_system numeric; v_id integer;
        v_when timestamp := COALESCE(p_reconciliationdate, (now() at time zone 'utc'));
BEGIN
    SELECT a.openingbalance + COALESCE((SELECT SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)
                                        FROM public.hotelcashtransactions t
                                        WHERE t.hotelcashaccountid = a.hotelcashaccountid AND t.farmid = a.farmid), 0)
    INTO   v_system
    FROM   public.hotelcashaccounts a
    WHERE  a.hotelcashaccountid = p_accountid AND a.farmid = p_farmid;
    IF v_system IS NULL THEN RAISE EXCEPTION 'Cash account not found.'; END IF;
    SELECT h.hotelcashreconciliationid INTO v_open FROM public.hotelcashreconciliations h
    WHERE  h.farmid = p_farmid AND h.hotelcashaccountid = p_accountid AND h.status = 'Draft' LIMIT 1;
    IF v_open IS NOT NULL THEN
        RAISE EXCEPTION 'This account already has an open cash count (#%). Finish or delete it first.', v_open;
    END IF;
    INSERT INTO public.hotelcashreconciliations
        (farmid, hotelcashaccountid, reconciliationdate, systembalance, actualbalance, difference,
         reason, notes, status, createdby)
    VALUES
        (p_farmid, p_accountid, v_when, v_system, p_actualbalance,
         CASE WHEN p_actualbalance IS NULL THEN 0 ELSE ROUND(p_actualbalance - v_system, 2) END,
         NULLIF(btrim(p_reason), ''), NULLIF(btrim(p_notes), ''), 'Draft', p_createdby)
    RETURNING hotelcashreconciliationid INTO v_id;
    UPDATE public.hotelcashreconciliations
    SET    referenceno = 'CC-' || to_char(v_when, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  hotelcashreconciliationid = v_id;
    RETURN v_id;
END;
$function$;

CREATE FUNCTION public.sphotelcashrecon_update(
    p_farmid             text,
    p_id                 integer,
    p_reconciliationdate timestamp DEFAULT NULL,
    p_actualbalance      numeric DEFAULT NULL,
    p_reason             text DEFAULT NULL,
    p_notes              text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v record; v_system numeric;
BEGIN
    SELECT * INTO v FROM public.hotelcashreconciliations h
    WHERE  h.hotelcashreconciliationid = p_id AND h.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash count % not found.', p_id; END IF;
    IF v.status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft cash count can be edited. This one is %. Start a new one.', v.status;
    END IF;
    SELECT a.openingbalance + COALESCE((SELECT SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)
                                        FROM public.hotelcashtransactions t
                                        WHERE t.hotelcashaccountid = a.hotelcashaccountid AND t.farmid = a.farmid), 0)
    INTO   v_system
    FROM   public.hotelcashaccounts a WHERE a.hotelcashaccountid = v.hotelcashaccountid;
    UPDATE public.hotelcashreconciliations
    SET    reconciliationdate = COALESCE(p_reconciliationdate, reconciliationdate),
           systembalance = v_system,
           actualbalance = p_actualbalance,
           difference = CASE WHEN p_actualbalance IS NULL THEN 0 ELSE ROUND(p_actualbalance - v_system, 2) END,
           reason = NULLIF(btrim(p_reason), ''), notes = NULLIF(btrim(p_notes), ''),
           updatedat = (now() at time zone 'utc')
    WHERE  hotelcashreconciliationid = p_id;
END;
$function$;

-- A draft moved no money, so discarding it is a delete; anything posted is
-- reversed instead.
CREATE FUNCTION public.sphotelcashrecon_delete(p_farmid text, p_id integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_status text;
BEGIN
    SELECT h.status INTO v_status FROM public.hotelcashreconciliations h
    WHERE  h.hotelcashreconciliationid = p_id AND h.farmid = p_farmid;
    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'A % cash count cannot be deleted -- reverse it instead, so the money history survives.', v_status;
    END IF;
    DELETE FROM public.hotelcashreconciliations WHERE hotelcashreconciliationid = p_id AND farmid = p_farmid;
END;
$function$;

-- Post: measure against the LEDGER now (healing the cache first, Poultry 223),
-- and post the difference as one adjustment row. Returns the ledger id, or
-- NULL when it balanced.
CREATE FUNCTION public.sphotelcashrecon_post(p_farmid text, p_id integer, p_postedby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE v record; a record; v_true numeric; v_diff numeric; v_txn integer;
BEGIN
    SELECT * INTO v FROM public.hotelcashreconciliations h
    WHERE  h.hotelcashreconciliationid = p_id AND h.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash count % not found.', p_id; END IF;
    IF v.status = 'Posted' THEN RETURN v.adjustmenttransactionid; END IF;
    IF v.status <> 'Draft' THEN RAISE EXCEPTION 'Cannot post a % cash count. Start a new one.', v.status; END IF;
    IF v.actualbalance IS NULL THEN RAISE EXCEPTION 'Enter the amount you counted before posting.'; END IF;

    SELECT * INTO a FROM public.hotelcashaccounts x
    WHERE  x.hotelcashaccountid = v.hotelcashaccountid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash account not found.'; END IF;
    IF v.actualbalance < 0 AND NOT a.allownegativebalance THEN
        RAISE EXCEPTION 'A counted balance cannot be negative on this account.';
    END IF;
    SELECT ROUND(a.openingbalance + COALESCE(SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END), 0), 2)
    INTO   v_true
    FROM   public.hotelcashtransactions t
    WHERE  t.hotelcashaccountid = a.hotelcashaccountid AND t.farmid = p_farmid;
    IF a.currentbalance IS DISTINCT FROM v_true THEN
        UPDATE public.hotelcashaccounts SET currentbalance = v_true, updatedat = now()
        WHERE  hotelcashaccountid = a.hotelcashaccountid;
    END IF;

    v_diff := ROUND(v.actualbalance - v_true, 2);   -- positive = over, negative = short
    IF v_diff <> 0 THEN
        v_txn := public.fnhotelcash_postonce(
            p_farmid, a.hotelcashaccountid,
            CASE WHEN v_diff > 0 THEN 'Credit' ELSE 'Debit' END, abs(v_diff),
            'Cash count ' || COALESCE(v.referenceno, '#' || p_id::text)
                || CASE WHEN v_diff > 0 THEN ' (over)' ELSE ' (short)' END
                || COALESCE(' - ' || NULLIF(btrim(v.reason), ''), ''),
            v.referenceno, 'ReconciliationAdjustment', p_id, p_postedby, v.reconciliationdate, TRUE);
    END IF;

    UPDATE public.hotelcashreconciliations
    SET    status = 'Posted', systembalance = v_true, systembalancecached = a.currentbalance,
           difference = v_diff, adjustmenttransactionid = v_txn,
           postedby = p_postedby, postedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc')
    WHERE  hotelcashreconciliationid = p_id;
    UPDATE public.hotelcashaccounts
    SET    lastreconciledat = v.reconciliationdate, lastreconciledbalance = v.actualbalance, updatedat = now()
    WHERE  hotelcashaccountid = a.hotelcashaccountid;
    RETURN v_txn;
END;
$function$;

CREATE FUNCTION public.sphotelcashrecon_reverse(p_farmid text, p_id integer, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v record; v_txn integer; v_prevat timestamp; v_prevbal numeric;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cash count.';
    END IF;
    SELECT * INTO v FROM public.hotelcashreconciliations h
    WHERE  h.hotelcashreconciliationid = p_id AND h.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash count % not found.', p_id; END IF;
    IF v.status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted cash count can be reversed (this one is %).', v.status;
    END IF;
    IF v.adjustmenttransactionid IS NOT NULL THEN
        v_txn := public.fnhotelcash_reverse(p_farmid, v.adjustmenttransactionid, 'ReconciliationReversal', p_reason, p_reversedby);
    END IF;
    UPDATE public.hotelcashreconciliations
    SET    status = 'Reversed', reversaltransactionid = v_txn, reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'), reversalreason = btrim(p_reason),
           updatedat = (now() at time zone 'utc')
    WHERE  hotelcashreconciliationid = p_id;
    -- The account's "last reconciled" falls back to the latest count still posted.
    SELECT h.reconciliationdate, h.actualbalance INTO v_prevat, v_prevbal
    FROM   public.hotelcashreconciliations h
    WHERE  h.farmid = p_farmid AND h.hotelcashaccountid = v.hotelcashaccountid AND h.status = 'Posted'
    ORDER  BY h.reconciliationdate DESC, h.hotelcashreconciliationid DESC LIMIT 1;
    UPDATE public.hotelcashaccounts
    SET    lastreconciledat = v_prevat, lastreconciledbalance = v_prevbal, updatedat = now()
    WHERE  hotelcashaccountid = v.hotelcashaccountid;
END;
$function$;

CREATE FUNCTION public.sphotelcashrecon_list(p_farmid text, p_accountid integer DEFAULT NULL)
RETURNS TABLE(
    hotelcashreconciliationid integer, hotelcashaccountid integer, accountname text, referenceno text,
    reconciliationdate timestamp, systembalance numeric, actualbalance numeric, difference numeric,
    reason text, notes text, status text, adjustmenttransactionid integer, createdby text,
    createdat timestamp, postedat timestamp, reversedat timestamp, reversalreason text
)
LANGUAGE sql STABLE
AS $function$
    SELECT h.hotelcashreconciliationid, h.hotelcashaccountid, a.accountname::text, h.referenceno,
           h.reconciliationdate, h.systembalance, h.actualbalance, h.difference,
           h.reason, h.notes, h.status, h.adjustmenttransactionid, h.createdby,
           h.createdat, h.postedat, h.reversedat, h.reversalreason
    FROM   public.hotelcashreconciliations h
    LEFT   JOIN public.hotelcashaccounts a ON a.hotelcashaccountid = h.hotelcashaccountid
    WHERE  h.farmid = p_farmid AND (p_accountid IS NULL OR h.hotelcashaccountid = p_accountid)
    ORDER  BY h.reconciliationdate DESC, h.hotelcashreconciliationid DESC;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Record Cash Adjustment (Poultry's adjust) -- amount is SIGNED
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelcashadjustment_record(
    p_farmid    text,
    p_accountid integer,
    p_amount    numeric,
    p_reason    text,
    p_createdby text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE v_id integer; v_txn integer; v_date timestamp := (now() at time zone 'utc');
BEGIN
    IF p_accountid IS NULL THEN RAISE EXCEPTION 'Choose the cash account the money moves through.'; END IF;
    IF COALESCE(p_amount, 0) = 0 THEN RAISE EXCEPTION 'An adjustment must be more than zero.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Say why the balance is changing.'; END IF;
    IF p_amount < 0 THEN
        PERFORM public.fnhotelcash_assertcanpay(p_farmid, p_accountid, abs(p_amount),
                                                'This adjustment would take the cash account below zero.');
    END IF;
    INSERT INTO public.hotelcashadjustments (farmid, hotelcashaccountid, adjustmentdate, amount, reason, createdby)
    VALUES (p_farmid, p_accountid, v_date, ROUND(p_amount, 2), btrim(p_reason), p_createdby)
    RETURNING hotelcashadjustmentid INTO v_id;
    UPDATE public.hotelcashadjustments
    SET    adjustmentnumber = 'ADJ-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  hotelcashadjustmentid = v_id;
    v_txn := public.fnhotelcash_postonce(p_farmid, p_accountid,
                 CASE WHEN p_amount > 0 THEN 'Credit' ELSE 'Debit' END, abs(ROUND(p_amount, 2)),
                 btrim(p_reason), NULL, 'CashAdjustment', v_id, p_createdby, v_date);
    UPDATE public.hotelcashadjustments SET cashtransactionid = v_txn WHERE hotelcashadjustmentid = v_id;
    RETURN v_id;
END;
$function$;

CREATE FUNCTION public.sphotelcashadjustment_reverse(p_farmid text, p_id integer, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v record; v_txn integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse an adjustment.'; END IF;
    SELECT * INTO v FROM public.hotelcashadjustments x
    WHERE  x.hotelcashadjustmentid = p_id AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Adjustment % not found.', p_id; END IF;
    IF v.status <> 'Posted' THEN RAISE EXCEPTION 'This adjustment is already reversed.'; END IF;
    IF v.amount > 0 THEN
        PERFORM public.fnhotelcash_assertcanpay(p_farmid, v.hotelcashaccountid, v.amount,
            'The cash account no longer holds this money; reversing the adjustment would overdraw it.');
    END IF;
    v_txn := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'CashAdjustmentReversal', p_reason, p_reversedby);
    UPDATE public.hotelcashadjustments
    SET    status = 'Reversed', reversalcashtransactionid = v_txn, reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'), reversalreason = btrim(p_reason)
    WHERE  hotelcashadjustmentid = p_id;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Cash Flow. Arms 1-10 are 327's, byte for byte (keep them when re-emitting).
--    New arms 11-15: owner money, loans, loan repayments, reconciliation and
--    cash adjustments -- each with its reversal as its own row, like 327.
--    Transfers have NO arm: both legs are the company's own money.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelcashflow_rows(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,        -- OperatingIn | OperatingOut | EmployeeLoanIn | EmployeeLoanOut
    createdat       timestamp)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. guest payments (the main revenue) --------------------------------
    -- Every payment on the day it was received, including one voided later:
    -- the void is its own row (1b) on the day it happened, as in the ledger.
    RETURN QUERY
    SELECT 'GuestPayment'::text,
           FALSE,
           hp.hotelpaymentid,
           hp.hotelcashaccountid,
           NULL::text,
           hp.paymentdate::timestamp,
           'CashIn'::text,
           'GuestPayment'::text,
           hp.hotelpaymentid,
           FALSE,
           COALESCE(hp.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(hp.notes), ''),
               NULLIF(btrim(hp.reference), ''),
               'Guest payment #' || hp.hotelpaymentid::text
           )::text,
           'OperatingIn'::text,
           hp.createdat::timestamp
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.paymentdate::timestamp >= v_from
      AND  hp.paymentdate::timestamp <= v_to;

    -- ---- 1b. guest payment voided (327) --------------------------------------
    RETURN QUERY
    SELECT 'GuestPaymentVoid'::text,
           FALSE,
           hp.hotelpaymentid,
           hp.hotelcashaccountid,
           NULL::text,
           hp.voidedat::timestamp,
           'CashOut'::text,
           'GuestPaymentVoid'::text,
           hp.hotelpaymentid,
           FALSE,
           -COALESCE(hp.amount, 0)::numeric,
           ('Void of guest payment #' || hp.hotelpaymentid::text
            || COALESCE(' - ' || NULLIF(btrim(hp.voidreason), ''), ''))::text,
           'OperatingOut'::text,
           hp.voidedat::timestamp
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  hp.status = 'Void'
      AND  hp.voidedat IS NOT NULL
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.voidedat::timestamp >= v_from
      AND  hp.voidedat::timestamp <= v_to;

    -- ---- 2. restaurant / F&B orders paid at the till (changed in 327) --------
    -- 316-325 required status 'Delivered', which the order screens never set,
    -- so this arm was always empty. The money arrives when the order is paid
    -- (placed and settled at the till: it has a POS ledger row). Orders charged
    -- to a room move no cash here -- they are on the folio and arrive through
    -- the guest's payment (arm 1).
    RETURN QUERY
    SELECT 'RestaurantOrder'::text,
           FALSE,
           ro.hotelrestaurantorderid,
           ro.hotelcashaccountid,
           NULL::text,
           ro.ordertime::timestamp,
           'CashIn'::text,
           'RestaurantOrder'::text,
           ro.hotelrestaurantorderid,
           FALSE,
           COALESCE(ro.totalamount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(ro.notes), ''),
               'Restaurant order #' || ro.hotelrestaurantorderid::text
               || COALESCE(' - Table ' || NULLIF(btrim(ro.tablenumber), ''), '')
           )::text,
           'OperatingIn'::text,
           ro.createdat::timestamp
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.cashtransactionid IS NOT NULL
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  ro.ordertime::timestamp >= v_from
      AND  ro.ordertime::timestamp <= v_to;

    -- ---- 2b. paid order cancelled: the money went back (327) ----------------
    RETURN QUERY
    SELECT 'RestaurantOrderReversal'::text,
           FALSE,
           ro.hotelrestaurantorderid,
           ro.hotelcashaccountid,
           NULL::text,
           ro.cancelledat::timestamp,
           'CashOut'::text,
           'RestaurantOrderReversal'::text,
           ro.hotelrestaurantorderid,
           FALSE,
           -COALESCE(ro.totalamount, 0)::numeric,
           ('Cancelled restaurant order #' || ro.hotelrestaurantorderid::text)::text,
           'OperatingOut'::text,
           ro.cancelledat::timestamp
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.reversalcashtransactionid IS NOT NULL
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  ro.cancelledat::timestamp >= v_from
      AND  ro.cancelledat::timestamp <= v_to;

    -- ---- 3. deposits collected (unchanged) -----------------------------------
    IF to_regclass('public.hoteldeposits') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'DepositIn'::text,
               FALSE,
               hd.hoteldepositid,
               hd.hotelcashaccountid,
               NULL::text,
               hd.createdat::timestamp,
               'CashIn'::text,
               'DepositCollected'::text,
               hd.hoteldepositid,
               FALSE,
               COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit collected #' || hd.hoteldepositid::text
               )::text,
               'OperatingIn'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Collected'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;

        -- ---- 4. deposits refunded (unchanged) --------------------------------
        RETURN QUERY
        SELECT 'DepositOut'::text,
               FALSE,
               hd.hoteldepositid,
               hd.hotelcashaccountid,
               NULL::text,
               hd.createdat::timestamp,
               'CashOut'::text,
               'DepositRefunded'::text,
               hd.hoteldepositid,
               FALSE,
               -COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit refunded #' || hd.hoteldepositid::text
               )::text,
               'OperatingOut'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Refunded'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;
    END IF;

    -- ---- 5. expenses (changed in 327) ----------------------------------------
    -- Approved/Paid as before. Two corrections: a Credit expense is a bill,
    -- not cash (its cash is the supplier payment, arm 9), and an approved
    -- expense cancelled later still spent the money on its day -- the refund is
    -- its own row (5b), as in the ledger.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           he.hotelexpenseid,
           he.hotelcashaccountid,
           NULL::text,
           he.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           he.hotelexpenseid,
           FALSE,
           -COALESCE(he.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(he.description), ''),
               COALESCE(he.category, 'Expense')
           )::text,
           'OperatingOut'::text,
           he.createdat::timestamp
    FROM   hotelexpenses he
    WHERE  lower(he.farmid::text) = lower(p_farmid)
      AND  COALESCE(he.amount, 0) > 0
      AND  COALESCE(he.paymentmethod, 'Cash') <> 'Credit'
      AND  (he.status IN ('Approved', 'Paid') OR he.cashtransactionid IS NOT NULL)
      AND  he.expensedate >= v_from
      AND  he.expensedate <= v_to;

    -- ---- 5b. approved expense cancelled: money back (327) --------------------
    RETURN QUERY
    SELECT 'ExpenseReversal'::text,
           FALSE,
           he.hotelexpenseid,
           he.hotelcashaccountid,
           NULL::text,
           he.cancelledat::timestamp,
           'CashIn'::text,
           'ExpenseReversal'::text,
           he.hotelexpenseid,
           FALSE,
           COALESCE(he.amount, 0)::numeric,
           ('Cancelled: ' || COALESCE(NULLIF(btrim(he.description), ''), COALESCE(he.category, 'Expense')))::text,
           'OperatingIn'::text,
           he.cancelledat::timestamp
    FROM   hotelexpenses he
    WHERE  lower(he.farmid::text) = lower(p_farmid)
      AND  he.reversalcashtransactionid IS NOT NULL
      AND  COALESCE(he.amount, 0) > 0
      AND  he.cancelledat::timestamp >= v_from
      AND  he.cancelledat::timestamp <= v_to;

    -- ---- 6. payroll (unchanged) ----------------------------------------------
    RETURN QUERY
    SELECT 'Payroll'::text,
           FALSE,
           pr.hotelpayrollrunid,
           pr.hotelcashaccountid,
           NULL::text,
           COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp,
           'CashOut'::text,
           'Payroll'::text,
           pr.hotelpayrollrunid,
           FALSE,
           -COALESCE(pr.totalnetpay, 0)::numeric,
           COALESCE(
               NULLIF(btrim(pr.notes), ''),
               'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY')
           )::text,
           'OperatingOut'::text,
           pr.createdat::timestamp
    FROM   hotelpayrollruns pr
    WHERE  lower(pr.farmid::text) = lower(p_farmid)
      AND  pr.status = 'Paid'
      AND  COALESCE(pr.totalnetpay, 0) > 0
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp >= v_from
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp <= v_to;

    -- ---- 7. staff loans and advances (325, unchanged) ------------------------
    IF to_regclass('public.hotelemployeeloans') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanDisbursed'::text,
               FALSE,
               l.hotelemployeeloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.disbursementdate::timestamp,
               'CashOut'::text,
               'EmployeeLoanDisbursement'::text,
               l.hotelemployeeloanid,
               FALSE,
               -(l.principalamount::numeric),
               ('Staff ' || CASE WHEN l.loantype = 'SalaryAdvance' THEN 'advance' ELSE 'loan' END
                || ' ' || COALESCE(l.loannumber, '') || ' to ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanOut'::text,
               l.createdat::timestamp
        FROM   hotelemployeeloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.cashtransactionid IS NOT NULL
          AND  l.disbursementdate::timestamp >= v_from
          AND  l.disbursementdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'LoanReversed'::text,
               FALSE,
               l.hotelemployeeloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.reversedat::timestamp,
               'CashIn'::text,
               'EmployeeLoanReversal'::text,
               l.hotelemployeeloanid,
               FALSE,
               l.principalamount::numeric,
               ('Reversal of staff loan ' || COALESCE(l.loannumber, '') || ' to ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanIn'::text,
               l.reversedat::timestamp
        FROM   hotelemployeeloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.reversalcashtransactionid IS NOT NULL
          AND  l.reversedat::timestamp >= v_from
          AND  l.reversedat::timestamp <= v_to;

        RETURN QUERY
        SELECT 'LoanRepaid'::text,
               FALSE,
               r.hotelemployeeloanrepaymentid,
               r.hotelcashaccountid,
               NULL::text,
               r.repaymentdate::timestamp,
               'CashIn'::text,
               'EmployeeLoanRepayment'::text,
               r.hotelemployeeloanid,
               FALSE,
               r.amount::numeric,
               ('Loan repayment ' || COALESCE(l.loannumber, '') || ' from ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanIn'::text,
               r.createdat::timestamp
        FROM   hotelemployeeloanrepayments r
        JOIN   hotelemployeeloans l ON l.hotelemployeeloanid = r.hotelemployeeloanid
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.cashtransactionid IS NOT NULL
          AND  r.repaymentdate::timestamp >= v_from
          AND  r.repaymentdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'LoanRepayReversed'::text,
               FALSE,
               r.hotelemployeeloanrepaymentid,
               r.hotelcashaccountid,
               NULL::text,
               r.reversedat::timestamp,
               'CashOut'::text,
               'EmployeeLoanRepaymentReversal'::text,
               r.hotelemployeeloanid,
               FALSE,
               -(r.amount::numeric),
               ('Reversal of loan repayment ' || COALESCE(l.loannumber, '') || ' from ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanOut'::text,
               r.reversedat::timestamp
        FROM   hotelemployeeloanrepayments r
        JOIN   hotelemployeeloans l ON l.hotelemployeeloanid = r.hotelemployeeloanid
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.reversalcashtransactionid IS NOT NULL
          AND  r.reversedat::timestamp >= v_from
          AND  r.reversedat::timestamp <= v_to;
    END IF;

    -- ---- 8. customer (corporate account) payments received (327) ------------
    -- Poultry arm 1: a receipt from a customer is Operating, on the day the
    -- money arrived.
    IF to_regclass('public.hotelcustomerpayments') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'CustomerPayment'::text,
               FALSE,
               cp.hotelcustomerpaymentid,
               cp.hotelcashaccountid,
               NULL::text,
               cp.paymentdate::timestamp,
               'CashIn'::text,
               'CustomerPayment'::text,
               cp.hotelcustomerpaymentid,
               FALSE,
               cp.amount::numeric,
               ('Customer payment' || COALESCE(' from ' || NULLIF(btrim(c.customername), ''), ''))::text,
               'OperatingIn'::text,
               cp.createdat::timestamp
        FROM   hotelcustomerpayments cp
        LEFT   JOIN hotelcustomers c ON c.hotelcustomerid = cp.hotelcustomerid
        WHERE  lower(cp.farmid::text) = lower(p_farmid)
          AND  cp.status = 'Approved'
          AND  cp.amount > 0
          AND  cp.paymentdate::timestamp >= v_from
          AND  cp.paymentdate::timestamp <= v_to;
    END IF;

    -- ---- 9. supplier payments made (327) -------------------------------------
    -- Poultry arm 3b: paying a supplier's bill is Operating, on the day paid.
    IF to_regclass('public.hotelsupplierpayments') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'SupplierPayment'::text,
               FALSE,
               sp.hotelsupplierpaymentid,
               sp.hotelcashaccountid,
               NULL::text,
               sp.paymentdate::timestamp,
               'CashOut'::text,
               'SupplierPayment'::text,
               sp.hotelsupplierpaymentid,
               FALSE,
               -(sp.amount::numeric),
               ('Supplier payment' || COALESCE(' to ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
               'OperatingOut'::text,
               sp.createdat::timestamp
        FROM   hotelsupplierpayments sp
        LEFT   JOIN hotelsuppliers s ON s.hotelsupplierid = sp.hotelsupplierid
        WHERE  lower(sp.farmid::text) = lower(p_farmid)
          AND  sp.status = 'Approved'
          AND  sp.amount > 0
          AND  sp.paymentdate::timestamp >= v_from
          AND  sp.paymentdate::timestamp <= v_to;
    END IF;

    -- ---- 10. capital asset purchases (327) -----------------------------------
    -- Poultry books an asset purchase as an expense row (costtype CapitalAsset)
    -- and its Cash Flow reports it in Operating Out; Hotel does the same here
    -- from the asset's posted cost entries. Asset cost entries carry no cash
    -- account, so this arm is the one movement with no ledger row
    -- (cashaccountid NULL) -- see the 327 report.
    IF to_regclass('public.hotelcapitalassetcosts') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'CapitalAsset'::text,
               FALSE,
               cc.hotelcapitalassetcostid,
               NULL::integer,
               NULL::text,
               COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp,
               'CashOut'::text,
               'CapitalAsset'::text,
               a.hotelcapitalassetid,
               FALSE,
               -(cc.amount::numeric),
               (COALESCE(NULLIF(btrim(a.assetname), ''), 'Asset')
                || COALESCE(' ' || a.assetnumber, '')
                || COALESCE(' - ' || NULLIF(btrim(cc.description), ''), ''))::text,
               'OperatingOut'::text,
               cc.createdat::timestamp
        FROM   hotelcapitalassetcosts cc
        JOIN   hotelcapitalassets a ON a.hotelcapitalassetid = cc.hotelcapitalassetid
        WHERE  lower(cc.farmid::text) = lower(p_farmid)
          AND  cc.status = 'Posted'
          AND  a.status <> 'Reversed'
          AND  cc.amount > 0
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp >= v_from
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp <= v_to;
    END IF;

    -- ---- 11. owner money (331, Poultry 253 arm 4) -----------------------------
    -- FINANCING, not operating: the owner funded the hotel or took funding back.
    -- Every record on its own day, including one reversed later; the reversal is
    -- its own row (11b) on the day it happened, as in the ledger.
    IF to_regclass('public.hotelownermoney') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'OwnerMoney'::text,
               FALSE,
               o.hotelownermoneyid,
               o.hotelcashaccountid,
               NULL::text,
               o.transactiondate::timestamp,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,
               o.hotelownermoneyid,
               FALSE,
               (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,
               COALESCE(NULLIF(btrim(o.notes), ''), NULLIF(btrim(o.ownername), ''),
                        CASE WHEN o.transactiontype = 'Contribution' THEN 'Owner contribution' ELSE 'Owner draw' END)::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
               o.createdat::timestamp
        FROM   hotelownermoney o
        WHERE  lower(o.farmid::text) = lower(p_farmid)
          AND  o.cashtransactionid IS NOT NULL
          AND  o.transactiondate::timestamp >= v_from
          AND  o.transactiondate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'OwnerMoneyReversal'::text,
               FALSE,
               o.hotelownermoneyid,
               o.hotelcashaccountid,
               NULL::text,
               o.reversedat::timestamp,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'CashOut' ELSE 'CashIn' END::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,
               o.hotelownermoneyid,
               FALSE,
               (CASE WHEN o.transactiontype = 'Contribution' THEN -o.amount ELSE o.amount END)::numeric,
               ('Reversal of ' || COALESCE(o.transactionnumber, 'owner money #' || o.hotelownermoneyid::text)
                || COALESCE(' - ' || NULLIF(btrim(o.reversalreason), ''), ''))::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingOut' ELSE 'FinancingIn' END::text,
               o.reversedat::timestamp
        FROM   hotelownermoney o
        WHERE  lower(o.farmid::text) = lower(p_farmid)
          AND  o.reversalcashtransactionid IS NOT NULL
          AND  o.reversedat::timestamp >= v_from
          AND  o.reversedat::timestamp <= v_to;
    END IF;

    -- ---- 12. loans received (331, Poultry 254 arm 5) --------------------------
    -- The AMOUNT RECEIVED, not the principal: only what arrived is cash in.
    -- Financing -- borrowed, not earned. A cancelled loan's money going back is
    -- its own row (12b).
    IF to_regclass('public.hotelloans') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'FinancingLoan'::text,
               FALSE,
               l.hotelloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.loandate::timestamp,
               'CashIn'::text,
               'LoanReceived'::text,
               l.hotelloanid,
               FALSE,
               l.amountreceived::numeric,
               ('Loan received from ' || l.lendername)::text,
               'FinancingIn'::text,
               l.createdat::timestamp
        FROM   hotelloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.cashtransactionid IS NOT NULL
          AND  l.amountreceived > 0
          AND  l.loandate::timestamp >= v_from
          AND  l.loandate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'FinancingLoanCancelled'::text,
               FALSE,
               l.hotelloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.reversedat::timestamp,
               'CashOut'::text,
               'LoanReceived'::text,
               l.hotelloanid,
               FALSE,
               -(l.amountreceived::numeric),
               ('Cancelled loan ' || COALESCE(l.loannumber, '#' || l.hotelloanid::text) || ' from ' || l.lendername)::text,
               'FinancingOut'::text,
               l.reversedat::timestamp
        FROM   hotelloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.reversalcashtransactionid IS NOT NULL
          AND  l.reversedat::timestamp >= v_from
          AND  l.reversedat::timestamp <= v_to;

        -- ---- 13. loan repayments (331, Poultry 254 arm 6) ---------------------
        -- The FULL payment leaves the account, so the full payment is money out
        -- -- principal, interest and fees together. The P&L counts only the
        -- interest and fees (from the same row); nothing here is counted twice.
        RETURN QUERY
        SELECT 'FinancingLoanPayment'::text,
               FALSE,
               p.hotelloanpaymentid,
               p.hotelcashaccountid,
               NULL::text,
               p.paymentdate::timestamp,
               'CashOut'::text,
               'LoanRepayment'::text,
               p.hotelloanid,
               FALSE,
               -(p.totalamount::numeric),
               ('Loan repayment to ' || l.lendername)::text,
               'FinancingOut'::text,
               p.createdat::timestamp
        FROM   hotelloanpayments p
        JOIN   hotelloans l ON l.hotelloanid = p.hotelloanid
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.cashtransactionid IS NOT NULL
          AND  p.paymentdate::timestamp >= v_from
          AND  p.paymentdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'FinancingLoanPaymentReversal'::text,
               FALSE,
               p.hotelloanpaymentid,
               p.hotelcashaccountid,
               NULL::text,
               p.reversedat::timestamp,
               'CashIn'::text,
               'LoanRepayment'::text,
               p.hotelloanid,
               FALSE,
               p.totalamount::numeric,
               ('Reversal of repayment ' || COALESCE(p.paymentnumber, '#' || p.hotelloanpaymentid::text)
                || ' to ' || l.lendername)::text,
               'FinancingIn'::text,
               p.reversedat::timestamp
        FROM   hotelloanpayments p
        JOIN   hotelloans l ON l.hotelloanid = p.hotelloanid
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.reversalcashtransactionid IS NOT NULL
          AND  p.reversedat::timestamp >= v_from
          AND  p.reversedat::timestamp <= v_to;
    END IF;

    -- ---- 14. reconciliation differences (331) ---------------------------------
    -- What a count found over or short, as posted. Operating (cash over/short),
    -- never an expense and never in the P&L. Amounts come from the ledger rows
    -- the count wrote, so this arm cannot disagree with the ledger.
    IF to_regclass('public.hotelcashreconciliations') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'ReconciliationAdjustment'::text,
               FALSE,
               h.hotelcashreconciliationid,
               h.hotelcashaccountid,
               NULL::text,
               t.txndate::timestamp,
               CASE WHEN t.txntype = 'Credit' THEN 'CashIn' ELSE 'CashOut' END::text,
               'ReconciliationAdjustment'::text,
               h.hotelcashreconciliationid,
               FALSE,
               (CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)::numeric,
               COALESCE(t.description, 'Cash count')::text,
               CASE WHEN t.txntype = 'Credit' THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
               t.createdat::timestamp
        FROM   hotelcashreconciliations h
        JOIN   hotelcashtransactions t ON t.hotelcashtxnid = h.adjustmenttransactionid
        WHERE  lower(h.farmid::text) = lower(p_farmid)
          AND  t.txndate::timestamp >= v_from
          AND  t.txndate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'ReconciliationReversal'::text,
               FALSE,
               h.hotelcashreconciliationid,
               h.hotelcashaccountid,
               NULL::text,
               t.txndate::timestamp,
               CASE WHEN t.txntype = 'Credit' THEN 'CashIn' ELSE 'CashOut' END::text,
               'ReconciliationAdjustment'::text,
               h.hotelcashreconciliationid,
               FALSE,
               (CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)::numeric,
               COALESCE(t.description, 'Reversal of cash count')::text,
               CASE WHEN t.txntype = 'Credit' THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
               t.createdat::timestamp
        FROM   hotelcashreconciliations h
        JOIN   hotelcashtransactions t ON t.hotelcashtxnid = h.reversaltransactionid
        WHERE  lower(h.farmid::text) = lower(p_farmid)
          AND  t.txndate::timestamp >= v_from
          AND  t.txndate::timestamp <= v_to;
    END IF;

    -- ---- 15. recorded cash adjustments (331) ---------------------------------
    -- sourcetype 'Adjustment' + the reason as description, exactly the shape
    -- lib/cash's flowLabel reads for Poultry's adjustments. An owner draw or
    -- contribution that was never recorded is Financing; everything else is
    -- Operating.
    IF to_regclass('public.hotelcashadjustments') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'CashAdjustment'::text,
               FALSE,
               x.hotelcashadjustmentid,
               x.hotelcashaccountid,
               NULL::text,
               x.adjustmentdate::timestamp,
               CASE WHEN x.amount > 0 THEN 'CashIn' ELSE 'CashOut' END::text,
               'Adjustment'::text,
               x.hotelcashadjustmentid,
               FALSE,
               x.amount::numeric,
               x.reason::text,
               (CASE WHEN x.reason IN ('Owner contribution not recorded', 'Owner draw not recorded')
                     THEN 'Financing' ELSE 'Operating' END
                || CASE WHEN x.amount > 0 THEN 'In' ELSE 'Out' END)::text,
               x.createdat::timestamp
        FROM   hotelcashadjustments x
        WHERE  lower(x.farmid::text) = lower(p_farmid)
          AND  x.cashtransactionid IS NOT NULL
          AND  x.adjustmentdate::timestamp >= v_from
          AND  x.adjustmentdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'CashAdjustmentReversal'::text,
               FALSE,
               x.hotelcashadjustmentid,
               x.hotelcashaccountid,
               NULL::text,
               x.reversedat::timestamp,
               CASE WHEN x.amount > 0 THEN 'CashOut' ELSE 'CashIn' END::text,
               'Adjustment'::text,
               x.hotelcashadjustmentid,
               FALSE,
               -(x.amount::numeric),
               x.reason::text,
               (CASE WHEN x.reason IN ('Owner contribution not recorded', 'Owner draw not recorded')
                     THEN 'Financing' ELSE 'Operating' END
                || CASE WHEN x.amount > 0 THEN 'Out' ELSE 'In' END)::text,
               x.reversedat::timestamp
        FROM   hotelcashadjustments x
        WHERE  lower(x.farmid::text) = lower(p_farmid)
          AND  x.reversalcashtransactionid IS NOT NULL
          AND  x.reversedat::timestamp >= v_from
          AND  x.reversedat::timestamp <= v_to;
    END IF;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Cash Flow detail: 327's categories plus the 331 rows.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelcashflow_detail(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,
    category        text,
    createdat       timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid,
           COALESCE(r.accountname, ca.accountname::text),
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource IN ('Expense', 'ExpenseReversal')
                   THEN COALESCE(
                       NULLIF(btrim(
                           COALESCE(ec.name, he.category)
                       ), ''),
                       'Uncategorised'
                   )
               WHEN r.rowsource IN ('GuestPayment', 'GuestPaymentVoid')
                   THEN COALESCE(
                       'Room revenue (' || NULLIF(btrim(hp.paymentmethod), '') || ')',
                       'Room revenue'
                   )
               WHEN r.rowsource IN ('RestaurantOrder', 'RestaurantOrderReversal') THEN 'Restaurant / F&B'
               WHEN r.rowsource = 'DepositIn'       THEN 'Guest deposits'
               WHEN r.rowsource = 'DepositOut'      THEN 'Deposit refunds'
               WHEN r.rowsource = 'Payroll'         THEN 'Staff wages'
               WHEN r.rowsource IN ('LoanDisbursed', 'LoanReversed')  THEN 'Staff loans & advances'
               WHEN r.rowsource IN ('LoanRepaid', 'LoanRepayReversed') THEN 'Staff loan repayments'
               WHEN r.rowsource = 'CustomerPayment' THEN 'Customer payments'
               WHEN r.rowsource = 'SupplierPayment' THEN 'Supplier payments'
               WHEN r.rowsource = 'CapitalAsset'    THEN 'Capital Asset'
               -- 331: Poultry's own category keys, so lib/cash labels them in
               -- Poultry's words; a reversal lands in its original's bucket.
               WHEN r.rowsource IN ('OwnerMoney', 'OwnerMoneyReversal',
                                    'FinancingLoan', 'FinancingLoanCancelled',
                                    'FinancingLoanPayment', 'FinancingLoanPaymentReversal',
                                    'ReconciliationAdjustment', 'ReconciliationReversal')
                   THEN r.sourcetype
               WHEN r.rowsource IN ('CashAdjustment', 'CashAdjustmentReversal')
                   THEN COALESCE(NULLIF(btrim(r.description), ''), 'Adjustment')
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.sphotelcashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN hotelcashaccounts ca
           ON  ca.hotelcashaccountid = r.cashaccountid
    LEFT   JOIN hotelexpenses he
           ON  r.rowsource IN ('Expense', 'ExpenseReversal')
           AND he.hotelexpenseid = r.sourcerowid
           AND lower(he.farmid::text) = lower(p_farmid)
    LEFT   JOIN hotelexpensecategories ec
           ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
    LEFT   JOIN hotelpayments hp
           ON  r.rowsource IN ('GuestPayment', 'GuestPaymentVoid')
           AND hp.hotelpaymentid = r.sourcerowid
           AND lower(hp.farmid::text) = lower(p_farmid);
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. Profit & Loss lines: 327's lines plus Loan Interest / Loan Fees & Charges
--     in the Depreciation & Financing band (the summary already sums every
--     OtherCost line, so sphotelreport_plsummary is unchanged). The expense
--     drilldown opens those two lines onto the repayments.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelreport_pllines(
    p_farmid    text,
    p_startdate date,
    p_enddate   date
) RETURNS TABLE(
    section         text,
    linekey         text,
    linelabel       text,
    amount          numeric,
    sortorder       integer,
    isinformational boolean,
    entrycount      integer
)
LANGUAGE sql STABLE
AS $function$
    WITH rev_payments AS (
        SELECT 'Revenue'::text   AS sec,
               'RoomRevenue'     AS k,
               'Room Revenue'    AS lbl,
               ROUND(COALESCE(SUM(hp.amount), 0), 2) AS amt,
               10                AS so,
               FALSE             AS info,
               COUNT(*)::integer AS n
        FROM   hotelpayments hp
        WHERE  lower(hp.farmid::text) = lower(p_farmid)
          AND  hp.status = 'Posted'
          AND  hp.paymentdate::date >= p_startdate
          AND  hp.paymentdate::date <= p_enddate
          AND  COALESCE(hp.amount, 0) > 0
    ),
    rev_restaurant AS (
        SELECT 'Revenue'::text       AS sec,
               'RestaurantRevenue'   AS k,
               'Restaurant / F&B'    AS lbl,
               ROUND(COALESCE(SUM(ro.totalamount), 0), 2) AS amt,
               20                    AS so,
               FALSE                 AS info,
               COUNT(*)::integer     AS n
        FROM   hotelrestaurantorders ro
        WHERE  lower(ro.farmid::text) = lower(p_farmid)
          AND  ro.cashtransactionid IS NOT NULL
          AND  ro.reversalcashtransactionid IS NULL
          AND  COALESCE(ro.totalamount, 0) > 0
          AND  ro.ordertime::date >= p_startdate
          AND  ro.ordertime::date <= p_enddate
    ),
    exp_payroll AS (
        SELECT 'OperatingExpense'::text AS sec,
               'StaffWages'             AS k,
               'Staff Wages'            AS lbl,
               ROUND(COALESCE(SUM(pr.totalgrosspay), 0), 2) AS amt,
               100                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelpayrollruns pr
        WHERE  lower(pr.farmid::text) = lower(p_farmid)
          AND  pr.status = 'Paid'
          AND  COALESCE(pr.totalgrosspay, 0) > 0
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date >= p_startdate
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date <= p_enddate
    ),
    rev_loaninterest AS (
        SELECT 'Revenue'::text              AS sec,
               'StaffLoanInterest'          AS k,
               'Interest on staff loans'    AS lbl,
               ROUND(COALESCE(SUM(r.interestamount), 0), 2) AS amt,
               40                           AS so,
               FALSE                        AS info,
               COUNT(*)::integer            AS n
        FROM   hotelemployeeloanrepayments r
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.status = 'Posted'
          AND  r.interestamount > 0
          AND  r.repaymentdate::date >= p_startdate
          AND  r.repaymentdate::date <= p_enddate
    ),
    exp_by_cat AS (
        SELECT 'OperatingExpense'::text AS sec,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS k,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS lbl,
               ROUND(SUM(he.amount), 2) AS amt,
               200                       AS so,
               FALSE                     AS info,
               COUNT(*)::integer         AS n
        FROM   hotelexpenses he
        LEFT   JOIN hotelexpensecategories ec
               ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
        WHERE  lower(he.farmid::text) = lower(p_farmid)
          AND  he.status IN ('Approved', 'Paid')
          AND  COALESCE(he.amount, 0) > 0
          AND  he.expensedate >= p_startdate
          AND  he.expensedate <= p_enddate
        GROUP BY COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised')
    ),
    -- Depreciation & Financing (327): posted monthly depreciation, non-cash.
    oth_depreciation AS (
        SELECT 'OtherCost'::text        AS sec,
               'Depreciation'           AS k,
               'Depreciation'           AS lbl,
               ROUND(COALESCE(SUM(d.amount), 0), 2) AS amt,
               300                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelassetdepreciation d
        WHERE  lower(d.farmid::text) = lower(p_farmid)
          AND  d.status = 'Posted'
          AND  d.periodstart >= p_startdate
          AND  d.periodstart <= p_enddate
    ),
    -- Depreciation & Financing (331): the cost of borrowing. Interest and fees
    -- from each posted loan repayment -- Poultry 272's LoanInterest / LoanFees
    -- lines. The principal is NOT here: repaying it is not a cost. The cash for
    -- the whole repayment is one Financing row on Cash Flow; this is the P&L's
    -- view of the same payment, so nothing is counted twice.
    oth_loaninterest AS (
        SELECT 'OtherCost'::text        AS sec,
               'LoanInterest'           AS k,
               'Loan Interest'          AS lbl,
               ROUND(COALESCE(SUM(p.interestamount), 0), 2) AS amt,
               310                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelloanpayments p
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted'
          AND  p.interestamount > 0
          AND  p.paymentdate::date >= p_startdate
          AND  p.paymentdate::date <= p_enddate
    ),
    oth_loanfees AS (
        SELECT 'OtherCost'::text        AS sec,
               'LoanFees'               AS k,
               'Loan Fees & Charges'    AS lbl,
               ROUND(COALESCE(SUM(p.feeamount), 0), 2) AS amt,
               320                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelloanpayments p
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted'
          AND  p.feeamount > 0
          AND  p.paymentdate::date >= p_startdate
          AND  p.paymentdate::date <= p_enddate
    ),
    all_lines AS (
        SELECT * FROM rev_payments
        UNION ALL SELECT * FROM rev_restaurant
        UNION ALL SELECT * FROM rev_loaninterest
        UNION ALL SELECT * FROM exp_payroll
        UNION ALL SELECT * FROM exp_by_cat
        UNION ALL SELECT * FROM oth_depreciation
        UNION ALL SELECT * FROM oth_loaninterest
        UNION ALL SELECT * FROM oth_loanfees
    )
    SELECT a.sec, a.k, a.lbl, a.amt, a.so, a.info, a.n
    FROM   all_lines a
    WHERE  a.amt <> 0
    ORDER  BY a.so, a.lbl;
$function$;

CREATE OR REPLACE FUNCTION public.sphotelreport_plexpensedetail(
    p_farmid    text,
    p_startdate date,
    p_enddate   date,
    p_linekey   text DEFAULT NULL
) RETURNS TABLE(
    hotelexpenseid       integer,
    expensedate          date,
    category             text,
    description          text,
    amount               numeric,
    vendor               text,
    paymentmethod        text,
    status               text,
    pllinekey            text
)
LANGUAGE sql STABLE
AS $function$
    SELECT * FROM (
        SELECT he.hotelexpenseid,
               he.expensedate,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised'),
               he.description::text,
               he.amount,
               he.vendor::text,
               he.paymentmethod::text,
               he.status::text,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised')
        FROM   hotelexpenses he
        LEFT   JOIN hotelexpensecategories ec
               ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
        WHERE  lower(he.farmid::text) = lower(p_farmid)
          AND  he.status IN ('Approved', 'Paid')
          AND  COALESCE(he.amount, 0) > 0
          AND  he.expensedate >= p_startdate
          AND  he.expensedate <= p_enddate
          AND  (p_linekey IS NULL
                OR COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') = p_linekey)

        UNION ALL

        SELECT d.hotelassetdepreciationid,
               d.periodstart,
               'Depreciation'::text,
               (COALESCE(a.assetname, 'Asset') || COALESCE(' ' || a.assetnumber, '')
                || ' - ' || to_char(d.periodstart, 'Mon YYYY'))::text,
               d.amount,
               NULL::text,
               'NonCash'::text,
               d.status::text,
               'Depreciation'::text
        FROM   hotelassetdepreciation d
        JOIN   hotelcapitalassets a ON a.hotelcapitalassetid = d.hotelcapitalassetid
        WHERE  p_linekey = 'Depreciation'
          AND  lower(d.farmid::text) = lower(p_farmid)
          AND  d.status = 'Posted'
          AND  d.periodstart >= p_startdate
          AND  d.periodstart <= p_enddate

        UNION ALL

        -- 331: the interest / fee parts of loan repayments, when their line is opened.
        SELECT p.hotelloanpaymentid,
               p.paymentdate::date,
               CASE WHEN p_linekey = 'LoanInterest' THEN 'Loan Interest' ELSE 'Loan Fees & Charges' END::text,
               ((CASE WHEN p_linekey = 'LoanInterest' THEN 'Interest on loan ' ELSE 'Fee on loan ' END)
                || COALESCE(l.loannumber, '#' || l.hotelloanid::text)
                || COALESCE(' - ' || p.paymentnumber, ''))::text,
               CASE WHEN p_linekey = 'LoanInterest' THEN p.interestamount ELSE p.feeamount END,
               l.lendername::text,
               'NonCash'::text,
               p.status::text,
               p_linekey::text
        FROM   hotelloanpayments p
        JOIN   hotelloans l ON l.hotelloanid = p.hotelloanid
        WHERE  p_linekey IN ('LoanInterest', 'LoanFees')
          AND  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted'
          AND  (CASE WHEN p_linekey = 'LoanInterest' THEN p.interestamount ELSE p.feeamount END) > 0
          AND  p.paymentdate::date >= p_startdate
          AND  p.paymentdate::date <= p_enddate
    ) x
    ORDER BY 2, 1;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. Cash Flow summary (316's body) -- now reports transfer volume: money
--     moved between the hotel's own accounts in the window. It is shown beside
--     the flow, never in Money In / Money Out.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelcashflow_summary(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    moneyin            numeric,
    moneyout           numeric,
    netcashflow        numeric,
    ledgercash         numeric,
    offledgernet       numeric,
    cashathand         numeric,
    openingbalance     numeric,
    transfervolume     numeric,
    offledgerin        numeric,
    offledgerout       numeric,
    rowcount           bigint)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_in      numeric := 0;
    v_out     numeric := 0;
    v_n       bigint  := 0;
    v_open    numeric := 0;
    v_trf     numeric := 0;
BEGIN
    SELECT COALESCE(SUM(r.amount)  FILTER (WHERE r.amount > 0), 0),
           COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0),
           COUNT(*)
      INTO v_in, v_out, v_n
    FROM   public.sphotelcashflow_rows(p_farmid, p_fromdate, p_todate) r;

    IF p_fromdate IS NOT NULL THEN
        SELECT COALESCE(SUM(r.amount), 0) INTO v_open
        FROM   public.sphotelcashflow_rows(
                   p_farmid, NULL, p_fromdate - interval '1 microsecond') r;
    END IF;

    IF to_regclass('public.hotelcashtransfers') IS NOT NULL THEN
        SELECT COALESCE(SUM(t.amount), 0) INTO v_trf
        FROM   public.hotelcashtransfers t
        WHERE  lower(t.farmid) = lower(p_farmid)
          AND  t.status = 'Approved'
          AND  (p_fromdate IS NULL OR t.transferdate >= p_fromdate)
          AND  (p_todate   IS NULL OR t.transferdate <= p_todate);
    END IF;

    RETURN QUERY SELECT
        ROUND(v_in, 2),
        ROUND(v_out, 2),
        ROUND(v_in - v_out, 2),
        0::numeric,                          -- ledgercash    (ledger not read)
        0::numeric,                          -- offledgernet  (concept retired)
        ROUND(v_open + v_in - v_out, 2),     -- cashathand = CLOSING cash
        ROUND(v_open, 2),
        ROUND(v_trf, 2),                     -- transfervolume (331)
        0::numeric,                          -- offledgerin
        0::numeric,                          -- offledgerout
        v_n;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. Verification (read-only)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
    FROM   unnest(ARRAY[
               'fnhotelcash_assertcanpay', 'sphotelcashaccount_update', 'sphotelcashaccount_countstatus',
               'sphotelcashaccount_recalculate',
               'sphotelownermoney_record', 'sphotelownermoney_reverse', 'sphotelownermoney_list', 'sphotelownermoney_summary',
               'sphotelloan_create', 'sphotelloan_update', 'sphotelloan_cancel', 'sphotelloan_list', 'sphotelloan_summary',
               'sphotelloanpayment_record', 'sphotelloanpayment_reverse', 'sphotelloanpayment_list',
               'sphotelcashtransfer_record', 'sphotelcashtransfer_reverse', 'sphotelcashtransfer_list',
               'sphotelcashrecon_insert', 'sphotelcashrecon_update', 'sphotelcashrecon_delete',
               'sphotelcashrecon_post', 'sphotelcashrecon_reverse', 'sphotelcashrecon_list',
               'sphotelcashadjustment_record', 'sphotelcashadjustment_reverse',
               'sphotelcashflow_rows', 'sphotelcashflow_detail', 'sphotelcashflow_summary',
               'sphotelreport_pllines', 'sphotelreport_plsummary', 'sphotelreport_plexpensedetail'
           ]) f
    WHERE  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '331 verification failed, missing: %', v_missing;
    END IF;

    -- Still one ledger writer: no other hotel function inserts into the ledger.
    IF EXISTS (SELECT 1 FROM pg_proc p
               WHERE (p.proname LIKE 'sphotel%' OR p.proname LIKE 'fnhotel%')
                 AND p.proname <> 'fnhotelcash_post'
                 AND p.prosrc ILIKE '%INSERT INTO public.hotelcashtransactions%') THEN
        RAISE EXCEPTION '331 verification failed: a hotel function writes the ledger directly';
    END IF;

    -- 327's arms are all still there, and 331's.
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'sphotelcashflow_rows'
                   AND prosrc LIKE '%''GuestPaymentVoid''%' AND prosrc LIKE '%''CapitalAsset''%'
                   AND prosrc LIKE '%''LoanRepayReversed''%' AND prosrc LIKE '%''OwnerMoneyReversal''%'
                   AND prosrc LIKE '%''CashAdjustmentReversal''%') THEN
        RAISE EXCEPTION '331 verification failed: sphotelcashflow_rows lost an arm';
    END IF;
END $$;

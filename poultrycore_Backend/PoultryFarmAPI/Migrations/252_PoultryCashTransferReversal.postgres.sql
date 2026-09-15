-- =============================================================================
-- 252_PoultryCashTransferReversal.postgres.sql
--
-- Purpose
-- -------
-- Poultry cash transfers can be made but never unmade.
--
-- sppoultrycashtransfer_cancel only accepts a transfer in status 'Draft', and
-- the Cash Accounts page calls _insert and then _approve back to back -- so
-- every transfer that exists is already Approved by the time a person could
-- click anything, and _cancel has never been able to touch one. A transfer
-- typed into the wrong account is permanent, and the only remedy today is a
-- second transfer in the opposite direction, which leaves the mistake and the
-- correction looking like two deliberate movements.
--
-- This file adds the reversal, plus the fields a transfer needs to be findable
-- afterwards: its own number and a reference.
--
-- HOW THE REVERSAL IS SHAPED
-- --------------------------
-- Append-only, like every other reversal in this codebase. The original
-- transfer keeps its status history and BOTH of its original cash rows; the
-- reversal adds two more, in the opposite direction. Nothing is deleted and no
-- balance is edited directly -- the account balances move because two more
-- ledger rows exist, which is the rule the whole cash module is built on.
--
-- THE ONE THING THAT MUST NOT BREAK
-- ---------------------------------
-- The reversal legs carry sourcetype = 'Transfer', exactly like the originals.
-- That is what keeps them INTERNAL:
--
--   231's cash-flow rows      excluded by (sourcetype = 'Transfer' OR ...)
--   lib/cash/cash-flow.ts     isInternalTransfer() checks sourceType first
--
-- If a reversal leg were written as an ordinary CashIn/CashOut, reversing a
-- transfer would inject money into company-wide Money In and Money Out that
-- the business never received or spent. The transactiontype is new --
-- 'TransferReversalIn' / 'TransferReversalOut' -- so a reconciliation screen
-- can tell a correction from a movement, but every classifier keys off
-- sourcetype and keeps treating all four rows as one internal movement.
--
-- (Poultry's live Cash Flow, migration 235, does not read the cash ledger at
-- all, so it cannot be affected either way. 231 still can, and the check file
-- pins both.)
--
-- THE DIRECTION OF THE GUARD FLIPS
-- --------------------------------
-- Approving a transfer checks the FROM account can afford it. Reversing one
-- takes the money back OUT of the TO account, so the same check has to run on
-- the destination -- otherwise a reversal can overdraw an account that a
-- transfer was never allowed to.
--
-- ALSO FIXED HERE
-- ---------------
-- _insert never checked that either account belongs to the farm being billed.
-- Both ids came straight from the request body, so a caller could move money
-- into another company's account. Spec section 37 asks for the check; it is
-- one EXISTS per account and it belongs with the rest of this work.
--
-- EFFECT ON TODAY'S NUMBERS: none. Five nullable columns, two id columns, a
-- backfill of transfer numbers on the 3 existing rows (a label, not an amount),
-- and functions. No balance and no ledger row is rewritten.
--
-- Order: after 251.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- _getall and _getbyid return two more columns, and _insert takes another
-- argument. CREATE OR REPLACE cannot change a return type, and leaving the old
-- _insert overload in place would let Npgsql bind either one by named argument
-- and silently drop the reference number.
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
          AND  p.proname IN ('sppoultrycashtransfer_insert',
                             'sppoultrycashtransfer_getall',
                             'sppoultrycashtransfer_getbyid',
                             'sppoultrycashtransfer_reverse')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The columns a transfer needs to be referred to and undone.
-- -----------------------------------------------------------------------------
ALTER TABLE poultrycashtransfers ADD COLUMN IF NOT EXISTS transfernumber   text NULL;
ALTER TABLE poultrycashtransfers ADD COLUMN IF NOT EXISTS referencenumber  text NULL;
ALTER TABLE poultrycashtransfers ADD COLUMN IF NOT EXISTS reversedby       text NULL;
ALTER TABLE poultrycashtransfers ADD COLUMN IF NOT EXISTS reversedat       timestamp NULL;
ALTER TABLE poultrycashtransfers ADD COLUMN IF NOT EXISTS reversalreason   text NULL;
-- The two legs approval wrote. Findable already through
-- (sourcetype = 'Transfer', sourceid), but stamping them makes the link one
-- lookup instead of a scan, and makes an orphaned leg obvious.
ALTER TABLE poultrycashtransfers ADD COLUMN IF NOT EXISTS outgoingcashtransactionid integer NULL;
ALTER TABLE poultrycashtransfers ADD COLUMN IF NOT EXISTS incomingcashtransactionid integer NULL;

COMMENT ON COLUMN poultrycashtransfers.transfernumber IS
    'TRF-YYYY-0001. Stamped after insert from the identity, the same race-free '
    'pattern the invoice and receipt numbers use.';
COMMENT ON COLUMN poultrycashtransfers.reversalreason IS
    'Required to reverse. Written to the audit trail; a reversal with no stated '
    'reason is indistinguishable from a mistake.';

-- Backfill the existing rows so no transfer is left without a number. This is
-- a LABEL, derived from data already on the row -- no amount, date, account or
-- status is touched.
UPDATE poultrycashtransfers
SET    transfernumber = 'TRF-' || to_char(COALESCE(transferdate, createdat), 'YYYY')
                        || '-' || lpad(poultrycashtransferid::text, 4, '0')
WHERE  transfernumber IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrycashtransfers_number
    ON poultrycashtransfers (farmid, transfernumber)
    WHERE transfernumber IS NOT NULL;

-- The reversal reads by farm and status; the page lists by date.
CREATE INDEX IF NOT EXISTS ix_poultrycashtransfers_farm_status
    ON poultrycashtransfers (farmid, status, transferdate DESC);

-- -----------------------------------------------------------------------------
-- 2. Insert: a reference number, and the ownership check that was missing.
--
-- Reproduced from the LIVE definition. The existing validations are unchanged;
-- the two EXISTS clauses and the reference column are new, and the number is
-- stamped after the row has an id.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashtransfer_insert(
    p_farmid                   text,
    p_frompoultrycashaccountid integer,
    p_topoultrycashaccountid   integer,
    p_amount                   numeric,
    p_transferdate             timestamp DEFAULT NULL,
    p_notes                    text DEFAULT NULL,
    p_createdby                text DEFAULT NULL,
    -- Appended, and defaulted, so a caller that predates this file still binds.
    p_referencenumber          text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_newid integer;
    v_date  timestamp;
BEGIN
    IF p_frompoultrycashaccountid = p_topoultrycashaccountid THEN
        RAISE EXCEPTION 'Cash transfer cannot be to the same account.';
    END IF;
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be greater than zero.';
    END IF;

    -- Both accounts must belong to THIS farm. Without this a transfer could
    -- name any account id in the database and move another company's money.
    IF NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                   WHERE a.poultrycashaccountid = p_frompoultrycashaccountid
                     AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Source cash account does not belong to this farm.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                   WHERE a.poultrycashaccountid = p_topoultrycashaccountid
                     AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Destination cash account does not belong to this farm.';
    END IF;

    v_date := COALESCE(p_transferdate, (now() at time zone 'utc'));

    INSERT INTO poultrycashtransfers (
        farmid, frompoultrycashaccountid, topoultrycashaccountid, transferdate, amount,
        status, notes, referencenumber, createdby
    )
    VALUES (
        p_farmid, p_frompoultrycashaccountid, p_topoultrycashaccountid,
        v_date, p_amount, 'Draft', p_notes, NULLIF(btrim(p_referencenumber), ''), p_createdby
    )
    RETURNING poultrycashtransferid INTO v_newid;

    UPDATE poultrycashtransfers
    SET    transfernumber = 'TRF-' || to_char(v_date, 'YYYY') || '-' || lpad(v_newid::text, 4, '0')
    WHERE  poultrycashtransferid = v_newid;

    RETURN v_newid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Approve: unchanged behaviour, but it now records which legs it wrote.
--
-- Reproduced from the LIVE definition. Every guard, every amount and both
-- ledger rows are exactly as they were; the only additions are RETURNING the
-- two new transaction ids onto the transfer.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashtransfer_approve(
    p_poultrycashtransferid integer,
    p_farmid                text,
    p_approvedby            text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_fromid      integer;
    v_toid        integer;
    v_amount      numeric;
    v_date        timestamp;
    v_status      text;
    v_frombalance numeric;
    v_allowneg    boolean;
    v_outid       integer;
    v_inid        integer;
BEGIN
    -- Already approved: idempotent no-op.
    IF EXISTS (SELECT 1 FROM poultrycashtransfers t
               WHERE t.poultrycashtransferid = p_poultrycashtransferid
                 AND t.farmid = p_farmid AND t.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT t.frompoultrycashaccountid, t.topoultrycashaccountid, t.amount, t.transferdate, t.status
    INTO   v_fromid, v_toid, v_amount, v_date, v_status
    FROM   poultrycashtransfers t
    WHERE  t.poultrycashtransferid = p_poultrycashtransferid AND t.farmid = p_farmid;

    IF v_fromid IS NULL THEN
        RAISE EXCEPTION 'Cash transfer % not found.', p_poultrycashtransferid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Cash transfer cannot be approved from status %.', v_status;
    END IF;

    SELECT a.currentbalance, a.allownegativebalance
    INTO   v_frombalance, v_allowneg
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = v_fromid;
    IF v_allowneg = FALSE AND (v_frombalance - v_amount) < 0 THEN
        RAISE EXCEPTION 'Source cash account would go negative; transfer rejected.';
    END IF;

    UPDATE poultrycashtransfers t
    SET    status = 'Approved', approvedby = p_approvedby, approvedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc')
    WHERE  t.poultrycashtransferid = p_poultrycashtransferid AND t.farmid = p_farmid;

    -- TransferOut leg
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, v_fromid, v_date, 'TransferOut',
        'Transfer', p_poultrycashtransferid, -v_amount, 'Transfer out',
        p_approvedby, p_approvedby, (now() at time zone 'utc')
    )
    RETURNING poultrycashtransactionid INTO v_outid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - v_amount, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = v_fromid;

    -- TransferIn leg
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, v_toid, v_date, 'TransferIn',
        'Transfer', p_poultrycashtransferid, v_amount, 'Transfer in',
        p_approvedby, p_approvedby, (now() at time zone 'utc')
    )
    RETURNING poultrycashtransactionid INTO v_inid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_amount, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = v_toid;

    UPDATE poultrycashtransfers t
    SET    outgoingcashtransactionid = v_outid,
           incomingcashtransactionid = v_inid
    WHERE  t.poultrycashtransferid = p_poultrycashtransferid AND t.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Reverse.
--
-- Two more ledger rows in the opposite direction, and the transfer marked. The
-- originals stay: what happened, happened.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashtransfer_reverse(
    p_poultrycashtransferid integer,
    p_farmid                text,
    p_reason                text,
    p_reversedby            text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_fromid    integer;
    v_toid      integer;
    v_amount    numeric;
    v_status    text;
    v_number    text;
    v_tobalance numeric;
    v_allowneg  boolean;
    v_now       timestamp := (now() at time zone 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cash transfer.';
    END IF;

    SELECT t.frompoultrycashaccountid, t.topoultrycashaccountid, t.amount, t.status, t.transfernumber
    INTO   v_fromid, v_toid, v_amount, v_status, v_number
    FROM   poultrycashtransfers t
    WHERE  t.poultrycashtransferid = p_poultrycashtransferid AND t.farmid = p_farmid;

    IF v_fromid IS NULL THEN
        RAISE EXCEPTION 'Cash transfer % not found.', p_poultrycashtransferid;
    END IF;
    -- A Draft moved no money, so there is nothing to put back: that is what
    -- _cancel is for. Reversing twice is refused rather than quietly doubling.
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Only an approved cash transfer can be reversed (this one is %).', v_status;
    END IF;

    -- The guard flips: the money comes back OUT of the destination.
    SELECT a.currentbalance, a.allownegativebalance
    INTO   v_tobalance, v_allowneg
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = v_toid;
    IF v_allowneg = FALSE AND (v_tobalance - v_amount) < 0 THEN
        RAISE EXCEPTION 'Destination cash account no longer holds this transfer; reversing it would overdraw the account.';
    END IF;

    -- Money leaves the destination. sourcetype stays 'Transfer' so every
    -- classifier still reads this as an internal movement; the transactiontype
    -- is what tells a reconciliation screen it is a correction.
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, v_toid, v_now, 'TransferReversalOut',
        'Transfer', p_poultrycashtransferid, -v_amount,
        'Reversal of transfer ' || COALESCE(v_number, p_poultrycashtransferid::text),
        p_reversedby, p_reversedby, v_now
    );

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - v_amount, updatedat = v_now
    WHERE  a.poultrycashaccountid = v_toid;

    -- And returns to the source.
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, v_fromid, v_now, 'TransferReversalIn',
        'Transfer', p_poultrycashtransferid, v_amount,
        'Reversal of transfer ' || COALESCE(v_number, p_poultrycashtransferid::text),
        p_reversedby, p_reversedby, v_now
    );

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_amount, updatedat = v_now
    WHERE  a.poultrycashaccountid = v_fromid;

    UPDATE poultrycashtransfers t
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = btrim(p_reason), updatedat = v_now
    WHERE  t.poultrycashtransferid = p_poultrycashtransferid AND t.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Reads, carrying the new fields.
--
-- Reproduced from the LIVE definitions; the joins, filter and ordering are
-- unchanged.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashtransfer_getall(
    p_farmid text,
    p_status text DEFAULT NULL
) RETURNS TABLE(
    poultrycashtransferid     integer,
    farmid                    text,
    transfernumber            text,
    frompoultrycashaccountid  integer,
    fromaccountname           text,
    topoultrycashaccountid    integer,
    toaccountname             text,
    transferdate              timestamp,
    amount                    numeric,
    status                    text,
    referencenumber           text,
    notes                     text,
    createdby                 text,
    approvedby                text,
    approvedat                timestamp,
    reversedby                text,
    reversedat                timestamp,
    reversalreason            text,
    outgoingcashtransactionid integer,
    incomingcashtransactionid integer,
    createdat                 timestamp,
    updatedat                 timestamp
)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT  t.poultrycashtransferid, t.farmid::text, t.transfernumber::text,
            t.frompoultrycashaccountid, fa.accountname::text,
            t.topoultrycashaccountid,   ta.accountname::text,
            t.transferdate, t.amount, t.status::text,
            t.referencenumber::text, t.notes::text,
            t.createdby::text, t.approvedby::text, t.approvedat,
            t.reversedby::text, t.reversedat, t.reversalreason::text,
            t.outgoingcashtransactionid, t.incomingcashtransactionid,
            t.createdat, t.updatedat
    FROM    poultrycashtransfers t
    INNER   JOIN poultrycashaccounts fa ON fa.poultrycashaccountid = t.frompoultrycashaccountid
    INNER   JOIN poultrycashaccounts ta ON ta.poultrycashaccountid = t.topoultrycashaccountid
    WHERE   t.farmid = p_farmid
       AND  (p_status IS NULL OR t.status = p_status)
    ORDER   BY t.transferdate DESC, t.poultrycashtransferid DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrycashtransfer_getbyid(
    p_poultrycashtransferid integer,
    p_farmid                text
) RETURNS TABLE(
    poultrycashtransferid     integer,
    farmid                    text,
    transfernumber            text,
    frompoultrycashaccountid  integer,
    fromaccountname           text,
    topoultrycashaccountid    integer,
    toaccountname             text,
    transferdate              timestamp,
    amount                    numeric,
    status                    text,
    referencenumber           text,
    notes                     text,
    createdby                 text,
    approvedby                text,
    approvedat                timestamp,
    reversedby                text,
    reversedat                timestamp,
    reversalreason            text,
    outgoingcashtransactionid integer,
    incomingcashtransactionid integer,
    createdat                 timestamp,
    updatedat                 timestamp
)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT g.* FROM sppoultrycashtransfer_getall(p_farmid, NULL) g
    WHERE  g.poultrycashtransferid = p_poultrycashtransferid;
END;
$function$;

COMMIT;

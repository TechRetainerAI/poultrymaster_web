-- =============================================================================
-- 456  Generic Cash Transfers + Reconciliation, brought up to Poultry's.
--
-- Poultry references: 252_PoultryCashTransferReversal (transfer number,
-- reference, reverse) and 223_PoultryCashReconciliation (draft -> edit -> post
-- -> discard -> reverse, account status, recalculate).
--
-- Generic's own tables only: genericcashtransfers, genericcashreconciliations,
-- genericcashtransactions, genericcashaccounts.
--
-- THE LEDGER TRUTH FOR A GENERIC ACCOUNT
-- -------------------------------------
-- A Generic opening balance is written as an 'OpeningBalance' transaction row
-- (spgenericcashaccount_insert), so the account's real balance is the sum of
-- its transaction rows. spgenericcashtransaction_reverse marks the ORIGINAL row
-- 'Reversed' and writes an 'Approved' opposite row, so BOTH must be summed --
-- summing 'Approved' only (as getdetails and the ledger report did) counts a
-- reversed entry's correction without the entry and reports the account short
-- by the reversed amount. fngenericcash_ledgerbalance is that rule in one
-- place; getdetails and the ledger report now use it.
--
-- Transfers stay out of Cash Flow: spgenericcashflow_rows has no transfer arm
-- and is not touched here.
--
-- Function changes (old signature dropped first where the parameter list or
-- RETURNS TABLE changed, so no second overload is left behind):
--   new      fngenericcash_ledgerbalance(text, integer)
--   replaced spgenericcashtransfer_insert      (+ p_referencenumber; stamps TRF number)
--   replaced spgenericcashtransfer_approve     (same signature; locks rows, clearer text)
--   new      spgenericcashtransfer_record      (create + approve in ONE call)
--   new      spgenericcashtransfer_reverse
--   replaced spgenericcashtransfer_getall / _getbyid (+ number, reference, reversal)
--   new      spgenericcashreconciliation_insert / _update / _delete / _post / _reverse
--   new      spgenericcashreconciliation_getaccountstatus
--   replaced spgenericcashreconciliation_getbyaccount (+ reference, posted/reversed)
--   replaced spgenericcashreconciliation_create (same signature; now draft + post)
--   new      spgenericcashaccount_reconcilebalance (recalculate cached balances)
--   replaced spgenericcashaccount_getdetails / spgenericcashledgerreport_get
--            (same signatures; ledger balance counts reversed rows too)
--
-- Runner wraps this file in one transaction.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A. Tables
-- -----------------------------------------------------------------------------
ALTER TABLE genericcashtransfers ADD COLUMN IF NOT EXISTS transfernumber  text         NULL;
ALTER TABLE genericcashtransfers ADD COLUMN IF NOT EXISTS referencenumber varchar(100) NULL;
ALTER TABLE genericcashtransfers ADD COLUMN IF NOT EXISTS reversedby      varchar(450) NULL;
ALTER TABLE genericcashtransfers ADD COLUMN IF NOT EXISTS reversedat      timestamp    NULL;
ALTER TABLE genericcashtransfers ADD COLUMN IF NOT EXISTS reversalreason  varchar(500) NULL;

UPDATE genericcashtransfers
SET    transfernumber = 'TRF-' || to_char(COALESCE(transferdate, createdat), 'YYYY')
                        || '-' || lpad(genericcashtransferid::text, 4, '0')
WHERE  transfernumber IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_genericcashtransfers_number
    ON genericcashtransfers (farmid, transfernumber) WHERE transfernumber IS NOT NULL;

-- A count is a draft until posted; a draft may not have a figure yet.
ALTER TABLE genericcashreconciliations ALTER COLUMN actualbalance DROP NOT NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS referenceno           text          NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS systembalancecached   numeric(14,2) NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS createdby             varchar(450)  NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS updatedat             timestamp     NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS postedby              varchar(450)  NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS postedat              timestamp     NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS reversedby            varchar(450)  NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS reversedat            timestamp     NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS reversalreason        varchar(500)  NULL;
ALTER TABLE genericcashreconciliations ADD COLUMN IF NOT EXISTS reversaltransactionid bigint        NULL;

-- Every existing row was written by the one-shot _create, which posted at once:
-- 'Approved' there meant what 'Posted' means now.
UPDATE genericcashreconciliations
SET    status   = 'Posted',
       postedby = COALESCE(postedby, approvedby, requestedby),
       postedat = COALESCE(postedat, createdat),
       createdby = COALESCE(createdby, requestedby)
WHERE  status = 'Approved';

UPDATE genericcashreconciliations
SET    referenceno = 'CC-' || to_char(reconciliationdate, 'YYYY') || '-'
                     || lpad(genericcashreconciliationid::text, 4, '0')
WHERE  referenceno IS NULL;

ALTER TABLE genericcashreconciliations ALTER COLUMN status SET DEFAULT 'Draft';

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'ck_genericcashrecon_status'
                     AND conrelid = 'genericcashreconciliations'::regclass) THEN
        ALTER TABLE genericcashreconciliations
            ADD CONSTRAINT ck_genericcashrecon_status CHECK (status IN ('Draft', 'Posted', 'Reversed'));
    END IF;
END $c$;

-- One open draft per account, as Poultry (ux_poultrycashrecon_one_draft).
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericcashrecon_one_draft
    ON genericcashreconciliations (farmid, genericcashaccountid) WHERE status = 'Draft';

-- -----------------------------------------------------------------------------
-- B. Ledger truth
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fngenericcash_ledgerbalance(p_farmid text, p_accountid integer)
RETURNS numeric
LANGUAGE sql STABLE
AS $f$
    SELECT COALESCE(SUM(t.amount), 0)::numeric
    FROM   genericcashtransactions t
    WHERE  t.farmid = p_farmid
      AND  t.genericcashaccountid = p_accountid
      AND  COALESCE(t.status, 'Approved') IN ('Approved', 'Reversed');
$f$;

-- Recalculate: rebuild every account's cached balance from its transactions.
-- Moves no money (Poultry's sppoultrycashaccount_reconcilebalance).
DROP FUNCTION IF EXISTS spgenericcashaccount_reconcilebalance(text);
CREATE FUNCTION spgenericcashaccount_reconcilebalance(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE v_n integer;
BEGIN
    UPDATE genericcashaccounts a
    SET    currentbalance = fngenericcash_ledgerbalance(a.farmid, a.genericcashaccountid),
           updatedat      = (now() at time zone 'utc')
    WHERE  a.farmid = p_farmid
      AND  a.currentbalance <> fngenericcash_ledgerbalance(a.farmid, a.genericcashaccountid);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END
$f$;

-- getdetails: same columns, ledgerbalance now counts reversed rows too.
CREATE OR REPLACE FUNCTION public.spgenericcashaccount_getdetails(p_farmid text, p_genericcashaccountid integer)
 RETURNS TABLE(genericcashaccountid integer, farmid text, accountname text, accounttype text, openingbalance numeric, currentbalance numeric, negativebalancepolicy text, negativebalancelimit numeric, isactive boolean, lastreconciledat timestamp without time zone, lastreconciledbalance numeric, totalmoneyin numeric, totalmoneyout numeric, transferin numeric, transferout numeric, totaladjustments numeric, ledgerbalance numeric, unreconciledcount integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        a.genericcashaccountid,
        a.farmid::text,
        a.accountname::text,
        a.accounttype::text,
        a.openingbalance,
        a.currentbalance,
        a.negativebalancepolicy::text,
        a.negativebalancelimit,
        a.isactive,
        a.lastreconciledat,
        a.lastreconciledbalance,
        COALESCE((SELECT SUM(t.amount) FROM genericcashtransactions t
                  WHERE t.genericcashaccountid = a.genericcashaccountid AND t.farmid = a.farmid
                    AND t.status = 'Approved' AND t.transactiontype = 'CashIn'
                    AND t.sourcetype <> 'OpeningBalance'), 0) AS totalmoneyin,
        COALESCE((SELECT SUM(-t.amount) FROM genericcashtransactions t
                  WHERE t.genericcashaccountid = a.genericcashaccountid AND t.farmid = a.farmid
                    AND t.status = 'Approved' AND t.transactiontype = 'CashOut'), 0) AS totalmoneyout,
        COALESCE((SELECT SUM(t.amount) FROM genericcashtransactions t
                  WHERE t.genericcashaccountid = a.genericcashaccountid AND t.farmid = a.farmid
                    AND t.status = 'Approved' AND t.transactiontype = 'TransferIn'), 0) AS transferin,
        COALESCE((SELECT SUM(-t.amount) FROM genericcashtransactions t
                  WHERE t.genericcashaccountid = a.genericcashaccountid AND t.farmid = a.farmid
                    AND t.status = 'Approved' AND t.transactiontype = 'TransferOut'), 0) AS transferout,
        COALESCE((SELECT SUM(t.amount) FROM genericcashtransactions t
                  WHERE t.genericcashaccountid = a.genericcashaccountid AND t.farmid = a.farmid
                    AND t.status = 'Approved'
                    AND (t.transactiontype = 'Adjustment'
                         OR t.sourcetype IN ('Adjustment','ReconciliationAdjustment'))), 0) AS totaladjustments,
        fngenericcash_ledgerbalance(a.farmid, a.genericcashaccountid) AS ledgerbalance,
        (SELECT COUNT(*)::int FROM genericcashtransactions t
         WHERE t.genericcashaccountid = a.genericcashaccountid AND t.farmid = a.farmid
           AND t.status = 'Approved'
           AND (a.lastreconciledat IS NULL OR t.transactiondate > a.lastreconciledat)) AS unreconciledcount
    FROM genericcashaccounts a
    WHERE a.genericcashaccountid = p_genericcashaccountid AND a.farmid = p_farmid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcashledgerreport_get(p_farmid text)
 RETURNS TABLE(genericcashaccountid integer, accountname text, accounttype text, currentbalance numeric, ledgerbalance numeric, discrepancy numeric, lastreconciledat timestamp without time zone, isactive boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        a.genericcashaccountid,
        a.accountname::text,
        a.accounttype::text,
        a.currentbalance,
        fngenericcash_ledgerbalance(a.farmid, a.genericcashaccountid) AS ledgerbalance,
        a.currentbalance - fngenericcash_ledgerbalance(a.farmid, a.genericcashaccountid) AS discrepancy,
        a.lastreconciledat,
        a.isactive
    FROM genericcashaccounts a
    WHERE a.farmid = p_farmid
    ORDER BY a.isactive DESC, a.accountname;
END;
$function$;

-- -----------------------------------------------------------------------------
-- C. Cash transfers
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericcashtransfer_insert(text, integer, integer, numeric, timestamp without time zone, text, text);
DROP FUNCTION IF EXISTS spgenericcashtransfer_insert(text, integer, integer, numeric, timestamp without time zone, text, text, text);
CREATE FUNCTION spgenericcashtransfer_insert(
    p_farmid text, p_fromgenericcashaccountid integer, p_togenericcashaccountid integer, p_amount numeric,
    p_transferdate timestamp without time zone DEFAULT NULL, p_notes text DEFAULT NULL,
    p_createdby text DEFAULT NULL, p_referencenumber text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_newid integer;
    v_date  timestamp := COALESCE(p_transferdate, (now() at time zone 'utc'));
BEGIN
    IF p_fromgenericcashaccountid IS NULL OR p_togenericcashaccountid IS NULL THEN
        RAISE EXCEPTION 'Pick both accounts.';
    END IF;
    IF (p_fromgenericcashaccountid = p_togenericcashaccountid) THEN
        RAISE EXCEPTION 'Source and destination cash accounts must be different.';
    END IF;
    IF (COALESCE(p_amount, 0) <= 0) THEN
        RAISE EXCEPTION 'Transfer amount must be greater than zero.';
    END IF;
    IF (SELECT count(*) FROM genericcashaccounts a
        WHERE a.farmid = p_farmid
          AND a.genericcashaccountid IN (p_fromgenericcashaccountid, p_togenericcashaccountid)) <> 2 THEN
        RAISE EXCEPTION 'One of the cash accounts on the transfer does not exist or belongs to another company.';
    END IF;

    INSERT INTO genericcashtransfers (
        farmid, fromgenericcashaccountid, togenericcashaccountid,
        transferdate, amount, status, notes, createdby, referencenumber
    )
    VALUES (
        p_farmid, p_fromgenericcashaccountid, p_togenericcashaccountid,
        v_date, p_amount, 'Draft', NULLIF(btrim(p_notes), ''), p_createdby, NULLIF(btrim(p_referencenumber), '')
    )
    RETURNING genericcashtransferid INTO v_newid;

    UPDATE genericcashtransfers
    SET    transfernumber = 'TRF-' || to_char(v_date, 'YYYY') || '-' || lpad(v_newid::text, 4, '0')
    WHERE  genericcashtransferid = v_newid;

    RETURN v_newid;
END;
$f$;

CREATE OR REPLACE FUNCTION spgenericcashtransfer_approve(p_genericcashtransferid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_fromid integer; v_toid integer; v_amount numeric; v_date timestamp;
    v_status text; v_notes text; v_number text;
    v_frombal numeric; v_fromneg boolean; v_fromname text;
    v_tobal numeric; v_toname text;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    SELECT tr.fromgenericcashaccountid, tr.togenericcashaccountid, tr.amount, tr.transferdate,
           tr.status, tr.notes, COALESCE(tr.transfernumber, '#' || tr.genericcashtransferid::text)
    INTO   v_fromid, v_toid, v_amount, v_date, v_status, v_notes, v_number
    FROM   genericcashtransfers tr
    WHERE  tr.genericcashtransferid = p_genericcashtransferid AND tr.farmid = p_farmid
    FOR UPDATE;

    IF v_fromid IS NULL THEN
        RAISE EXCEPTION 'Cash transfer % not found.', p_genericcashtransferid;
    END IF;
    IF v_status = 'Approved' THEN RETURN; END IF;   -- idempotent
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Cash transfer cannot be approved from status %.', v_status;
    END IF;

    -- Lock both accounts in a fixed order so two transfers cannot deadlock.
    PERFORM 1 FROM genericcashaccounts a
    WHERE  a.farmid = p_farmid AND a.genericcashaccountid IN (v_fromid, v_toid)
    ORDER  BY a.genericcashaccountid FOR UPDATE;

    SELECT a.currentbalance, a.allownegativebalance, a.accountname
    INTO   v_frombal, v_fromneg, v_fromname
    FROM   genericcashaccounts a WHERE a.genericcashaccountid = v_fromid AND a.farmid = p_farmid;
    SELECT a.currentbalance, a.accountname
    INTO   v_tobal, v_toname
    FROM   genericcashaccounts a WHERE a.genericcashaccountid = v_toid AND a.farmid = p_farmid;

    IF (v_frombal IS NULL OR v_tobal IS NULL) THEN
        RAISE EXCEPTION 'One of the cash accounts on the transfer does not exist or belongs to another company.';
    END IF;
    IF (v_frombal - v_amount < 0 AND v_fromneg = FALSE) THEN
        RAISE EXCEPTION 'Not enough money in %: it holds %, the transfer is %. The account is not allowed to go negative.',
            v_fromname, v_frombal, v_amount;
    END IF;

    UPDATE genericcashtransfers tr
    SET    status = 'Approved', approvedby = p_approvedby, approvedat = v_now, updatedat = v_now
    WHERE  tr.genericcashtransferid = p_genericcashtransferid AND tr.farmid = p_farmid;

    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
        amount, balanceaftertransaction, description, status, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, v_fromid, v_date, 'TransferOut', 'Transfer', p_genericcashtransferid,
        -v_amount, v_frombal - v_amount,
        left('Transfer ' || v_number || ' to ' || v_toname || COALESCE(' - ' || v_notes, ''), 500),
        'Approved', p_approvedby, p_approvedby, v_now);

    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
        amount, balanceaftertransaction, description, status, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, v_toid, v_date, 'TransferIn', 'Transfer', p_genericcashtransferid,
        v_amount, v_tobal + v_amount,
        left('Transfer ' || v_number || ' from ' || v_fromname || COALESCE(' - ' || v_notes, ''), 500),
        'Approved', p_approvedby, p_approvedby, v_now);

    UPDATE genericcashaccounts a SET currentbalance = v_frombal - v_amount, updatedat = v_now
    WHERE  a.genericcashaccountid = v_fromid AND a.farmid = p_farmid;
    UPDATE genericcashaccounts a SET currentbalance = v_tobal + v_amount, updatedat = v_now
    WHERE  a.genericcashaccountid = v_toid AND a.farmid = p_farmid;
END;
$f$;

-- Create and approve in one call: a failure anywhere leaves no Draft behind.
DROP FUNCTION IF EXISTS spgenericcashtransfer_record(text, integer, integer, numeric, timestamp without time zone, text, text, text);
CREATE FUNCTION spgenericcashtransfer_record(
    p_farmid text, p_fromgenericcashaccountid integer, p_togenericcashaccountid integer, p_amount numeric,
    p_transferdate timestamp without time zone DEFAULT NULL, p_referencenumber text DEFAULT NULL,
    p_notes text DEFAULT NULL, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE v_id integer;
BEGIN
    v_id := spgenericcashtransfer_insert(
        p_farmid => p_farmid, p_fromgenericcashaccountid => p_fromgenericcashaccountid,
        p_togenericcashaccountid => p_togenericcashaccountid, p_amount => p_amount,
        p_transferdate => p_transferdate, p_notes => p_notes, p_createdby => p_by,
        p_referencenumber => p_referencenumber);
    PERFORM spgenericcashtransfer_approve(v_id, p_farmid, p_by);
    RETURN v_id;
END;
$f$;

-- Undo an APPROVED transfer: two opposite rows, the originals kept, the reason
-- audited (Poultry's sppoultrycashtransfer_reverse). sourcetype stays
-- 'Transfer' so every reader keeps treating it as an internal move.
DROP FUNCTION IF EXISTS spgenericcashtransfer_reverse(integer, text, text, text);
CREATE FUNCTION spgenericcashtransfer_reverse(
    p_genericcashtransferid integer, p_farmid text, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_fromid integer; v_toid integer; v_amount numeric; v_status text; v_number text;
    v_frombal numeric; v_tobal numeric; v_toneg boolean; v_toname text; v_fromname text;
    v_outleg bigint; v_inleg bigint;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cash transfer.';
    END IF;

    SELECT t.fromgenericcashaccountid, t.togenericcashaccountid, t.amount, t.status,
           COALESCE(t.transfernumber, '#' || t.genericcashtransferid::text)
    INTO   v_fromid, v_toid, v_amount, v_status, v_number
    FROM   genericcashtransfers t
    WHERE  t.genericcashtransferid = p_genericcashtransferid AND t.farmid = p_farmid
    FOR UPDATE;

    IF v_fromid IS NULL THEN
        RAISE EXCEPTION 'Cash transfer % not found.', p_genericcashtransferid;
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Only an approved cash transfer can be reversed (this one is %).', v_status;
    END IF;

    -- If a leg was already undone on the ledger page, reversing the transfer
    -- would move that money a second time.
    IF EXISTS (SELECT 1 FROM genericcashtransactions x
               WHERE x.farmid = p_farmid AND x.sourcetype = 'Transfer' AND x.sourceid = p_genericcashtransferid
                 AND x.status = 'Reversed') THEN
        RAISE EXCEPTION 'A ledger row of transfer % was already reversed on its own; it cannot be reversed again as a whole.', v_number;
    END IF;

    PERFORM 1 FROM genericcashaccounts a
    WHERE  a.farmid = p_farmid AND a.genericcashaccountid IN (v_fromid, v_toid)
    ORDER  BY a.genericcashaccountid FOR UPDATE;

    SELECT a.currentbalance, a.accountname INTO v_frombal, v_fromname
    FROM   genericcashaccounts a WHERE a.genericcashaccountid = v_fromid AND a.farmid = p_farmid;
    SELECT a.currentbalance, a.allownegativebalance, a.accountname INTO v_tobal, v_toneg, v_toname
    FROM   genericcashaccounts a WHERE a.genericcashaccountid = v_toid AND a.farmid = p_farmid;

    IF v_toneg = FALSE AND (v_tobal - v_amount) < 0 THEN
        RAISE EXCEPTION '% no longer holds this transfer (it has %); reversing it would overdraw the account.',
            v_toname, v_tobal;
    END IF;

    SELECT x.genericcashtransactionid INTO v_outleg FROM genericcashtransactions x
    WHERE  x.farmid = p_farmid AND x.sourcetype = 'Transfer' AND x.sourceid = p_genericcashtransferid
      AND  x.transactiontype = 'TransferOut' AND x.reversaloftransactionid IS NULL
    ORDER  BY x.genericcashtransactionid LIMIT 1;
    SELECT x.genericcashtransactionid INTO v_inleg FROM genericcashtransactions x
    WHERE  x.farmid = p_farmid AND x.sourcetype = 'Transfer' AND x.sourceid = p_genericcashtransferid
      AND  x.transactiontype = 'TransferIn' AND x.reversaloftransactionid IS NULL
    ORDER  BY x.genericcashtransactionid LIMIT 1;

    -- Money leaves the destination ...
    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
        amount, balanceaftertransaction, description, status, createdby, approvedby, approvedat,
        reversaloftransactionid, notes)
    VALUES (
        p_farmid, v_toid, v_now, 'TransferOut', 'Transfer', p_genericcashtransferid,
        -v_amount, v_tobal - v_amount, 'Reversal of transfer ' || v_number,
        'Approved', p_reversedby, p_reversedby, v_now, v_inleg, btrim(p_reason));
    UPDATE genericcashaccounts a SET currentbalance = v_tobal - v_amount, updatedat = v_now
    WHERE  a.genericcashaccountid = v_toid AND a.farmid = p_farmid;

    -- ... and returns to the source.
    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
        amount, balanceaftertransaction, description, status, createdby, approvedby, approvedat,
        reversaloftransactionid, notes)
    VALUES (
        p_farmid, v_fromid, v_now, 'TransferIn', 'Transfer', p_genericcashtransferid,
        v_amount, v_frombal + v_amount, 'Reversal of transfer ' || v_number,
        'Approved', p_reversedby, p_reversedby, v_now, v_outleg, btrim(p_reason));
    UPDATE genericcashaccounts a SET currentbalance = v_frombal + v_amount, updatedat = v_now
    WHERE  a.genericcashaccountid = v_fromid AND a.farmid = p_farmid;

    UPDATE genericcashtransfers t
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = left(btrim(p_reason), 500), updatedat = v_now
    WHERE  t.genericcashtransferid = p_genericcashtransferid AND t.farmid = p_farmid;
END;
$f$;

DROP FUNCTION IF EXISTS spgenericcashtransfer_getall(text, text);
CREATE FUNCTION spgenericcashtransfer_getall(p_farmid text, p_status text DEFAULT NULL::text)
RETURNS TABLE(genericcashtransferid integer, farmid text, transfernumber text,
              fromgenericcashaccountid integer, fromaccountname text,
              togenericcashaccountid integer, toaccountname text,
              transferdate timestamp without time zone, amount numeric, status text,
              referencenumber text, notes text, createdby text, approvedby text,
              approvedat timestamp without time zone, reversedby text,
              reversedat timestamp without time zone, reversalreason text,
              createdat timestamp without time zone, updatedat timestamp without time zone)
LANGUAGE plpgsql
AS $f$
BEGIN
    RETURN QUERY
    SELECT t.genericcashtransferid, t.farmid::text, t.transfernumber::text, t.fromgenericcashaccountid,
           af.accountname::text, t.togenericcashaccountid, ato.accountname::text,
           t.transferdate, t.amount, t.status::text, t.referencenumber::text, t.notes::text,
           t.createdby::text, t.approvedby::text, t.approvedat, t.reversedby::text, t.reversedat,
           t.reversalreason::text, t.createdat, t.updatedat
    FROM   genericcashtransfers t
    INNER  JOIN genericcashaccounts af  ON af.genericcashaccountid  = t.fromgenericcashaccountid
    INNER  JOIN genericcashaccounts ato ON ato.genericcashaccountid = t.togenericcashaccountid
    WHERE  t.farmid = p_farmid
       AND (p_status IS NULL OR t.status = p_status)
    ORDER  BY t.transferdate DESC, t.genericcashtransferid DESC;
END;
$f$;

DROP FUNCTION IF EXISTS spgenericcashtransfer_getbyid(integer, text);
CREATE FUNCTION spgenericcashtransfer_getbyid(p_genericcashtransferid integer, p_farmid text)
RETURNS TABLE(genericcashtransferid integer, farmid text, transfernumber text,
              fromgenericcashaccountid integer, fromaccountname text,
              togenericcashaccountid integer, toaccountname text,
              transferdate timestamp without time zone, amount numeric, status text,
              referencenumber text, notes text, createdby text, approvedby text,
              approvedat timestamp without time zone, reversedby text,
              reversedat timestamp without time zone, reversalreason text,
              createdat timestamp without time zone, updatedat timestamp without time zone)
LANGUAGE plpgsql
AS $f$
BEGIN
    RETURN QUERY
    SELECT g.* FROM spgenericcashtransfer_getall(p_farmid, NULL) g
    WHERE  g.genericcashtransferid = p_genericcashtransferid;
END;
$f$;

-- -----------------------------------------------------------------------------
-- D. Reconciliation (cash count): draft -> edit -> post -> discard -> reverse
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericcashreconciliation_insert(text, integer, timestamp without time zone, numeric, text, text, text);
CREATE FUNCTION spgenericcashreconciliation_insert(
    p_farmid text, p_genericcashaccountid integer,
    p_reconciliationdate timestamp without time zone DEFAULT NULL, p_actualbalance numeric DEFAULT NULL,
    p_reason text DEFAULT NULL, p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_when   timestamp := COALESCE(p_reconciliationdate, (now() at time zone 'utc'));
    v_ledger numeric;
    v_open   text;
    v_id     integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM genericcashaccounts a
                   WHERE a.genericcashaccountid = p_genericcashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account not found.';
    END IF;
    SELECT COALESCE(r.referenceno, '#' || r.genericcashreconciliationid::text) INTO v_open
    FROM   genericcashreconciliations r
    WHERE  r.farmid = p_farmid AND r.genericcashaccountid = p_genericcashaccountid AND r.status = 'Draft'
    LIMIT  1;
    IF v_open IS NOT NULL THEN
        RAISE EXCEPTION 'This account already has an unposted count (%). Post or discard it first.', v_open;
    END IF;

    v_ledger := fngenericcash_ledgerbalance(p_farmid, p_genericcashaccountid);

    INSERT INTO genericcashreconciliations (
        farmid, genericcashaccountid, reconciliationdate, systembalance, actualbalance, difference,
        reason, notes, status, requestedby, createdby, createdat)
    VALUES (
        p_farmid, p_genericcashaccountid, v_when, v_ledger, p_actualbalance,
        COALESCE(p_actualbalance - v_ledger, 0),
        NULLIF(btrim(p_reason), ''), NULLIF(btrim(p_notes), ''), 'Draft', p_createdby, p_createdby,
        (now() at time zone 'utc'))
    RETURNING genericcashreconciliationid INTO v_id;

    UPDATE genericcashreconciliations
    SET    referenceno = 'CC-' || to_char(v_when, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  genericcashreconciliationid = v_id;

    RETURN v_id;
END;
$f$;

DROP FUNCTION IF EXISTS spgenericcashreconciliation_update(integer, text, timestamp without time zone, numeric, text, text, text);
CREATE FUNCTION spgenericcashreconciliation_update(
    p_genericcashreconciliationid integer, p_farmid text,
    p_reconciliationdate timestamp without time zone DEFAULT NULL, p_actualbalance numeric DEFAULT NULL,
    p_reason text DEFAULT NULL, p_notes text DEFAULT NULL, p_updatedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE v_status text; v_acct integer; v_ledger numeric;
BEGIN
    SELECT r.status, r.genericcashaccountid INTO v_status, v_acct
    FROM   genericcashreconciliations r
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid
    FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Cash count not found.'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft count can be edited (this one is %).', v_status;
    END IF;

    v_ledger := fngenericcash_ledgerbalance(p_farmid, v_acct);

    UPDATE genericcashreconciliations r
    SET    reconciliationdate = COALESCE(p_reconciliationdate, r.reconciliationdate),
           actualbalance      = p_actualbalance,
           systembalance      = v_ledger,
           difference         = COALESCE(p_actualbalance - v_ledger, 0),
           reason             = NULLIF(btrim(p_reason), ''),
           notes              = NULLIF(btrim(p_notes), ''),
           updatedat          = (now() at time zone 'utc')
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid;
END;
$f$;

DROP FUNCTION IF EXISTS spgenericcashreconciliation_delete(integer, text, text);
CREATE FUNCTION spgenericcashreconciliation_delete(
    p_genericcashreconciliationid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE v_status text;
BEGIN
    SELECT r.status INTO v_status FROM genericcashreconciliations r
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid
    FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Cash count not found.'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft count can be discarded (this one is %). Reverse a posted count instead.', v_status;
    END IF;
    DELETE FROM genericcashreconciliations r
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid;
END;
$f$;

-- Post: re-measure against the ledger NOW, post the difference, heal the cache.
DROP FUNCTION IF EXISTS spgenericcashreconciliation_post(integer, text, text);
CREATE FUNCTION spgenericcashreconciliation_post(
    p_genericcashreconciliationid integer, p_farmid text, p_postedby text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
AS $f$
DECLARE
    v_status text; v_acct integer; v_actual numeric; v_when timestamp; v_reason text; v_ref text;
    v_cached numeric; v_ledger numeric; v_diff numeric; v_adjid bigint := NULL;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    SELECT r.status, r.genericcashaccountid, r.actualbalance, r.reconciliationdate, r.reason,
           COALESCE(r.referenceno, '#' || r.genericcashreconciliationid::text)
    INTO   v_status, v_acct, v_actual, v_when, v_reason, v_ref
    FROM   genericcashreconciliations r
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid
    FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Cash count not found.'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft count can be posted (this one is %).', v_status;
    END IF;
    IF v_actual IS NULL THEN
        RAISE EXCEPTION 'Enter the counted amount before posting.';
    END IF;

    SELECT a.currentbalance INTO v_cached FROM genericcashaccounts a
    WHERE  a.genericcashaccountid = v_acct AND a.farmid = p_farmid FOR UPDATE;
    v_ledger := fngenericcash_ledgerbalance(p_farmid, v_acct);
    v_diff   := v_actual - v_ledger;

    IF v_diff <> 0 THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
            amount, balanceaftertransaction, description, status, createdby, approvedby, approvedat, notes)
        VALUES (
            p_farmid, v_acct, v_when, CASE WHEN v_diff > 0 THEN 'CashIn' ELSE 'CashOut' END,
            'ReconciliationAdjustment', p_genericcashreconciliationid, v_diff, v_actual,
            'Cash count ' || v_ref || ' (' || CASE WHEN v_diff > 0 THEN 'over' ELSE 'short' END || ')',
            'Approved', p_postedby, p_postedby, v_now, v_reason)
        RETURNING genericcashtransactionid INTO v_adjid;
    END IF;

    -- The balance becomes what was counted; this also heals a drifted cache.
    UPDATE genericcashaccounts a
    SET    currentbalance = v_actual,
           lastreconciledat = CASE WHEN a.lastreconciledat IS NULL OR v_when >= a.lastreconciledat
                                   THEN v_when ELSE a.lastreconciledat END,
           lastreconciledbalance = CASE WHEN a.lastreconciledat IS NULL OR v_when >= a.lastreconciledat
                                        THEN v_actual ELSE a.lastreconciledbalance END,
           updatedat = v_now
    WHERE  a.genericcashaccountid = v_acct AND a.farmid = p_farmid;

    UPDATE genericcashreconciliations r
    SET    status = 'Posted', systembalance = v_ledger, systembalancecached = v_cached,
           difference = v_diff, adjustmenttransactionid = v_adjid,
           postedby = p_postedby, postedat = v_now, approvedby = p_postedby, updatedat = v_now
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid;

    RETURN v_adjid;
END;
$f$;

-- Reverse a posted count: an opposite adjustment via the ledger's own reversal,
-- the original kept, the account's last-counted point rolled back.
DROP FUNCTION IF EXISTS spgenericcashreconciliation_reverse(integer, text, text, text);
CREATE FUNCTION spgenericcashreconciliation_reverse(
    p_genericcashreconciliationid integer, p_farmid text, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_status text; v_acct integer; v_adjid bigint; v_revid bigint := NULL;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cash count.';
    END IF;
    SELECT r.status, r.genericcashaccountid, r.adjustmenttransactionid INTO v_status, v_acct, v_adjid
    FROM   genericcashreconciliations r
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid
    FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Cash count not found.'; END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted count can be reversed (this one is %).', v_status;
    END IF;

    IF v_adjid IS NOT NULL THEN
        SELECT x.genericcashtransactionid INTO v_revid
        FROM   spgenericcashtransaction_reverse(v_adjid, p_farmid, p_reversedby, btrim(p_reason)) x;
    END IF;

    UPDATE genericcashreconciliations r
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = left(btrim(p_reason), 500), reversaltransactionid = v_revid, updatedat = v_now
    WHERE  r.genericcashreconciliationid = p_genericcashreconciliationid AND r.farmid = p_farmid;

    -- Last counted = the latest count still standing.
    UPDATE genericcashaccounts a
    SET    lastreconciledat      = l.reconciliationdate,
           lastreconciledbalance = l.actualbalance,
           updatedat             = v_now
    FROM  (SELECT NULL::int AS k) d
    LEFT  JOIN LATERAL (
        SELECT r.reconciliationdate, r.actualbalance
        FROM   genericcashreconciliations r
        WHERE  r.farmid = p_farmid AND r.genericcashaccountid = v_acct AND r.status = 'Posted'
        ORDER  BY r.reconciliationdate DESC, r.genericcashreconciliationid DESC
        LIMIT  1) l ON TRUE
    WHERE  a.genericcashaccountid = v_acct AND a.farmid = p_farmid;
END;
$f$;

-- The one-shot route (POST cash/reconciliations) keeps working: draft + post.
CREATE OR REPLACE FUNCTION public.spgenericcashreconciliation_create(p_farmid text, p_genericcashaccountid integer, p_actualbalance numeric, p_reconciliationdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_reason text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_requestedby text DEFAULT NULL::text, p_approvedby text DEFAULT NULL::text)
 RETURNS TABLE(genericcashreconciliationid integer, difference numeric, adjustmenttransactionid bigint)
 LANGUAGE plpgsql
AS $f$
DECLARE v_id integer; v_adj bigint;
BEGIN
    IF p_actualbalance IS NULL THEN RAISE EXCEPTION 'Enter the counted amount.'; END IF;
    v_id  := spgenericcashreconciliation_insert(p_farmid, p_genericcashaccountid, p_reconciliationdate,
                                                p_actualbalance, p_reason, p_notes, p_requestedby);
    v_adj := spgenericcashreconciliation_post(v_id, p_farmid, COALESCE(p_approvedby, p_requestedby));
    RETURN QUERY
    SELECT r.genericcashreconciliationid, r.difference, v_adj
    FROM   genericcashreconciliations r WHERE r.genericcashreconciliationid = v_id;
END;
$f$;

DROP FUNCTION IF EXISTS spgenericcashreconciliation_getbyaccount(integer, text);
CREATE FUNCTION spgenericcashreconciliation_getbyaccount(p_genericcashaccountid integer, p_farmid text)
RETURNS TABLE(genericcashreconciliationid integer, farmid text, genericcashaccountid integer, accountname text,
              accounttype text, referenceno text, reconciliationdate timestamp without time zone,
              systembalance numeric, systembalancecached numeric, actualbalance numeric, difference numeric,
              adjustmenttransactionid bigint, reversaltransactionid bigint, reason text, notes text, status text,
              requestedby text, approvedby text, createdby text, createdat timestamp without time zone,
              updatedat timestamp without time zone, postedby text, postedat timestamp without time zone,
              reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE plpgsql
AS $f$
BEGIN
    RETURN QUERY
    SELECT r.genericcashreconciliationid, r.farmid::text, r.genericcashaccountid, a.accountname::text,
           a.accounttype::text, r.referenceno::text, r.reconciliationdate,
           r.systembalance, r.systembalancecached, r.actualbalance, r.difference,
           r.adjustmenttransactionid, r.reversaltransactionid, r.reason::text, r.notes::text, r.status::text,
           r.requestedby::text, r.approvedby::text, r.createdby::text, r.createdat,
           r.updatedat, r.postedby::text, r.postedat, r.reversedby::text, r.reversedat, r.reversalreason::text
    FROM   genericcashreconciliations r
    INNER  JOIN genericcashaccounts a ON a.genericcashaccountid = r.genericcashaccountid
    WHERE  r.genericcashaccountid = p_genericcashaccountid AND r.farmid = p_farmid
    ORDER  BY r.reconciliationdate DESC, r.genericcashreconciliationid DESC;
END;
$f$;

-- Per-account status for the Reconciliation page tiles (Poultry's
-- sppoultrycashreconciliation_getaccountstatus). Generic has no per-entry
-- clearing, so "uncleared" = entries dated after the last posted count.
DROP FUNCTION IF EXISTS spgenericcashreconciliation_getaccountstatus(text);
CREATE FUNCTION spgenericcashreconciliation_getaccountstatus(p_farmid text)
RETURNS TABLE(genericcashaccountid integer, accountname text, accounttype text, isactive boolean,
              currentbalance numeric, ledgerbalance numeric, cachedrift numeric,
              lastreconciledat timestamp without time zone, lastreconciledbalance numeric,
              dayssincereconciled integer, unclearedcount integer, unclearedamount numeric,
              opendraftid integer)
LANGUAGE sql STABLE
AS $f$
    SELECT a.genericcashaccountid, a.accountname::text, a.accounttype::text, a.isactive,
           a.currentbalance,
           fngenericcash_ledgerbalance(a.farmid, a.genericcashaccountid),
           ROUND(a.currentbalance - fngenericcash_ledgerbalance(a.farmid, a.genericcashaccountid), 2),
           a.lastreconciledat, a.lastreconciledbalance,
           CASE WHEN a.lastreconciledat IS NULL THEN NULL
                ELSE EXTRACT(DAY FROM (now() at time zone 'utc') - a.lastreconciledat)::integer END,
           COALESCE(u.n, 0)::integer, COALESCE(u.amt, 0)::numeric,
           d.genericcashreconciliationid
    FROM   genericcashaccounts a
    LEFT   JOIN LATERAL (
        SELECT count(*) AS n, SUM(t.amount) AS amt
        FROM   genericcashtransactions t
        WHERE  t.farmid = a.farmid AND t.genericcashaccountid = a.genericcashaccountid
          AND  COALESCE(t.status, 'Approved') IN ('Approved', 'Reversed')
          AND  (a.lastreconciledat IS NULL OR t.transactiondate > a.lastreconciledat)
    ) u ON TRUE
    LEFT   JOIN LATERAL (
        SELECT h.genericcashreconciliationid
        FROM   genericcashreconciliations h
        WHERE  h.farmid = a.farmid AND h.genericcashaccountid = a.genericcashaccountid AND h.status = 'Draft'
        LIMIT  1
    ) d ON TRUE
    WHERE  a.farmid = p_farmid
    ORDER  BY a.accountname;
$f$;

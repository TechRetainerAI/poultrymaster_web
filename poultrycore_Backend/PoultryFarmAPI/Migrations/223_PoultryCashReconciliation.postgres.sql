-- =============================================================================
-- 223_PoultryCashReconciliation.postgres.sql
--
-- Purpose
-- -------
-- A cash account's balance is whatever the system's own transactions add up to.
-- Nothing ever contradicts it. Cash goes missing, bank charges land unrecorded,
-- a driver returns short, a payment is entered against the wrong account -- and
-- the figure on screen stays confidently wrong.
--
-- This adds a CASH COUNT: someone counts the drawer (or reads the bank/MoMo
-- balance), the system compares it to the ledger, and the difference is posted
-- as an adjustment transaction. The balance becomes something a person checked
-- rather than something the software asserted.
--
-- Port of migration 222 (Water)
-- -----------------------------
-- 222 built this for Water; 111 built an earlier, thinner version for Generic.
-- Poultry's cash schema (migrations 128/129) is a column-for-column port of
-- Water's (047/048), so this migration is a faithful port of 222 with the names
-- changed. Four things were re-checked against Poultry rather than assumed, and
-- one of them differs -- see below.
--
-- Checked against Poultry, NOT assumed
-- ------------------------------------
--   1. Opening balance is NOT a ledger row. spPoultryCashAccount_Insert (129)
--      seeds CurrentBalance = OpeningBalance and writes no transaction, exactly
--      as Water does. So the balance identity here is
--      openingbalance + SUM(amount), the same as 222 -- and NOT Generic's, where
--      migration 108 made opening a row.
--   2. spPoultryCashAccount_Adjust (129) writes SourceType 'Adjustment' with
--      SourceId NULL and returns nothing. So _post below inlines its own ledger
--      insert for the same four reasons 222 gives: the delta rule and the
--      adjustmenttransactionid linkage need a SourceId to key on, the id cannot
--      be captured from it, 'Adjustment' would make a counted correction
--      indistinguishable from someone typing -50 into the Adjust box, and its
--      Postgres body is not in this repo. Reuse buys no atomicity either -- a
--      plpgsql function called from another shares the caller's transaction.
--   3. spPoultryCashAccount_ReconcileBalance (129) is byte-for-byte Water's:
--      currentbalance is a denormalised cache that drifts, and _post heals it
--      before counting.
--   4. DIFFERENT FROM WATER: spPoultryCashAccount_Delete (129) is a SOFT delete
--      -- it sets IsActive = 0 and never removes the row. Water's hard-deletes
--      an account with no transactions, which is why 222 needed ON DELETE
--      CASCADE on the header's account FK. Here nothing hard-deletes, so that
--      cascade is belt-and-braces rather than load-bearing. It is kept anyway:
--      if Poultry ever gains a hard-delete path, a draft count must not be what
--      makes an account undeletable.
--
-- One deliberate difference from 111
-- ----------------------------------
-- It does:
--     UPDATE GenericCashAccounts SET CurrentBalance = @ActualBalance
-- Poultry forbids that, as Water does. currentbalance moves only by "± amount"
-- alongside a ledger row, and 129's spPoultryCashAccount_ReconcileBalance would
-- overwrite a directly-set value on its next run anyway. We post the DIFFERENCE
-- and let the balance follow -- arithmetically identical, concurrency-safe, and
-- it survives a later recalculation because the correction lives in the ledger.
--
-- "Reconcile" is already taken, twice
-- -----------------------------------
--   spPoultryCashAccount_ReconcileBalance (129)   = recompute the cached balance
--   POST /Poultry/cash-accounts/reconcile-balances = the same thing over the API
-- Neither is a cash count. This migration therefore names its table
-- poultrycashreconciliations but keeps the ROUTE and the UI wording distinct
-- ("Cash count" vs "Recalculate balances"). Do not merge the two ideas.
--
-- Additive on function surface, by necessity
-- ------------------------------------------
-- Migrations 001-210 are T-SQL kept as the logic of record; the live Postgres
-- functions were converted elsewhere and their bodies are not in this repo.
-- Migration 216 had to read fnpoultrydailyclosing_livetotals out of pg_proc and
-- patch its text precisely because of this. CREATE OR REPLACE cannot change a
-- RETURNS TABLE column list, so altering sppoultrycashtransaction_getbyfarm
-- would mean DROP plus rewriting a body nobody here can read.
--
-- So: NEW FUNCTIONS ONLY, ZERO DROPS. The clearing columns are exposed through a
-- new sppoultrycashtransaction_getledger rather than by editing the existing
-- read.
--
-- THE DAILY-CLOSING TRAP -- read before extending this
-- ----------------------------------------------------
-- fnpoultrydailyclosing_livetotals derives expected cash at hand as
-- (sales - credit sales) + customer collections - EXPENSES. Every migration that
-- defines or redefines it (148, 149, 151, 152) was checked: none of them
-- reference poultrycashtransactions or poultrycashaccounts. So a cash-account
-- adjustment CANNOT distort poultry daily closing, and migration 216's carve-out
-- technique is not needed here.
--
-- The corollary is the danger, and Poultry has already been bitten by it. The
-- leak would be through the Expense table, which daily closing DOES read --
-- migration 216 had to surgically carve non-cash internal-use expenses back out
-- of that very function. "Book the bank charge as an expense" is a natural
-- follow-up request, and acting on it would silently understate expected cash
-- every single day. THIS FEATURE MUST NEVER WRITE AN Expense ROW. The reason
-- field carries the categorisation instead.
--
-- Also note poultrydailyclosings already has cashathand/actualcashcounted/
-- cashdifference. That is a per-DAY count against a DERIVED expectation. This is
-- a per-ACCOUNT count against the LEDGER. They measure different things, will
-- never agree, and neither writes to the other.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
-- CREATE OR REPLACE FUNCTION, delta-based posting.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Last-counted marker on the account (111's LastReconciledAt/Balance).
-- -----------------------------------------------------------------------------
ALTER TABLE poultrycashaccounts ADD COLUMN IF NOT EXISTS lastreconciledat      timestamp     NULL;
ALTER TABLE poultrycashaccounts ADD COLUMN IF NOT EXISTS lastreconciledbalance numeric(14,2) NULL;

-- -----------------------------------------------------------------------------
-- 2. The cash count header.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultrycashreconciliations (
    poultrycashreconciliationid serial PRIMARY KEY,
    farmid                    text          NOT NULL,
    -- ON DELETE CASCADE, though nothing currently triggers it: unlike Water's,
    -- spPoultryCashAccount_Delete (129) is a soft delete that only sets
    -- IsActive = 0. The cascade is here so that if a hard-delete path is ever
    -- added, a forgotten draft count is not what makes an account undeletable.
    -- A POSTED count always implies transactions, so such a path would have to
    -- deactivate the account anyway and nothing would cascade.
    poultrycashaccountid        integer       NOT NULL
        REFERENCES poultrycashaccounts (poultrycashaccountid) ON DELETE CASCADE,
    referenceno               text          NULL,
    reconciliationdate        timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),

    -- What the LEDGER says: openingbalance + SUM(amount). Note Poultry's identity
    -- includes openingbalance because opening is NOT a ledger row here -- unlike
    -- Generic, where migration 108 made it one.
    -- Snapshotted on insert so a draft has something to show, and RECOMPUTED on
    -- post, because other cash can land between drafting and posting.
    systembalance             numeric(14,2) NOT NULL DEFAULT 0,
    -- What poultrycashaccounts.currentbalance claimed at post time. Equal to
    -- systembalance unless the denormalised cache had drifted; kept so a count
    -- can explain a cache repair it made on the way through.
    systembalancecached       numeric(14,2) NULL,
    -- NULL while drafting: an unopened count has no number, and 0 is a real count.
    actualbalance             numeric(14,2) NULL,
    difference                numeric(14,2) NOT NULL DEFAULT 0,   -- actual - system

    adjustmenttransactionid   integer       NULL
        REFERENCES poultrycashtransactions (poultrycashtransactionid),
    reversaltransactionid     integer       NULL
        REFERENCES poultrycashtransactions (poultrycashtransactionid),

    clearedcount              integer       NOT NULL DEFAULT 0,
    clearedamount             numeric(14,2) NOT NULL DEFAULT 0,

    reason                    text          NULL,
    notes                     text          NULL,
    status                    text          NOT NULL DEFAULT 'Draft',  -- Draft|Posted|Reversed

    createdby                 text          NULL,
    createdat                 timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat                 timestamp     NULL,
    postedby                  text          NULL,
    postedat                  timestamp     NULL,
    reversedby                text          NULL,
    reversedat                timestamp     NULL,
    reversalreason            text          NULL
);

CREATE INDEX IF NOT EXISTS ix_poultrycashrecon_farm_account
    ON poultrycashreconciliations (farmid, poultrycashaccountid, reconciliationdate DESC);
CREATE INDEX IF NOT EXISTS ix_poultrycashrecon_farm_status
    ON poultrycashreconciliations (farmid, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrycashrecon_farm_ref
    ON poultrycashreconciliations (farmid, referenceno) WHERE referenceno IS NOT NULL;
-- One open count per account, enforced in the database. Two people counting the
-- same drawer at once produce two contradictory differences and both get posted.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrycashrecon_one_draft
    ON poultrycashreconciliations (farmid, poultrycashaccountid) WHERE status = 'Draft';

-- -----------------------------------------------------------------------------
-- 3. Clearing status on the ledger.
-- -----------------------------------------------------------------------------
-- On PostgreSQL 11+ a NOT NULL DEFAULT is a catalog-only change: no table
-- rewrite, and every existing row reads back as 'Uncleared' with no UPDATE.
-- THAT IS THE BACKFILL, and it is deliberate -- marking a year of history
-- 'Cleared' would be a claim nobody authorised. Adoption is an explicit operator
-- action; see sppoultrycashtransaction_clearbefore in section 5.
ALTER TABLE poultrycashtransactions
    ADD COLUMN IF NOT EXISTS clearingstatus            text          NOT NULL DEFAULT 'Uncleared';
ALTER TABLE poultrycashtransactions
    ADD COLUMN IF NOT EXISTS cleareddate               timestamp     NULL;
ALTER TABLE poultrycashtransactions
    ADD COLUMN IF NOT EXISTS clearedby                 text          NULL;
-- The count that cleared this row. NULL = never cleared, or cleared by hand.
-- Detailed bank/MoMo matching is out of scope, but when it lands it adds its own
-- nullable statement-line id beside this one; neither displaces the other.
ALTER TABLE poultrycashtransactions
    ADD COLUMN IF NOT EXISTS poultrycashreconciliationid integer       NULL;
ALTER TABLE poultrycashtransactions
    ADD COLUMN IF NOT EXISTS clearingnotes             text          NULL;

DO $fk$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_poultrycashtxn_reconciliation') THEN
        ALTER TABLE poultrycashtransactions
            ADD CONSTRAINT fk_poultrycashtxn_reconciliation
            FOREIGN KEY (poultrycashreconciliationid)
            REFERENCES poultrycashreconciliations (poultrycashreconciliationid)
            ON DELETE SET NULL;
    END IF;
END;
$fk$;

CREATE INDEX IF NOT EXISTS ix_poultrycashtxn_uncleared
    ON poultrycashtransactions (farmid, poultrycashaccountid, transactiondate)
    WHERE clearingstatus <> 'Cleared';
CREATE INDEX IF NOT EXISTS ix_poultrycashtxn_reconciliation
    ON poultrycashtransactions (poultrycashreconciliationid)
    WHERE poultrycashreconciliationid IS NOT NULL;

-- clearingstatus vocabulary: Uncleared | Cleared | Disputed.
-- 'Disputed' is unused by this build and included on purpose: it is the one
-- value that would be expensive to retrofit once bank matching arrives, because
-- every filter, index predicate and rollup would need rewriting. Validated in
-- the SPs with RAISE EXCEPTION rather than a table CHECK, matching how `status`
-- is handled everywhere else in this schema (see 128's note).

-- -----------------------------------------------------------------------------
-- 4. Draft lifecycle: insert / update / delete.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_insert(
    p_farmid             text,
    p_poultrycashaccountid integer,
    p_reconciliationdate timestamp DEFAULT NULL,
    p_actualbalance      numeric   DEFAULT NULL,
    p_reason             text      DEFAULT NULL,
    p_notes              text      DEFAULT NULL,
    p_createdby          text      DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_opening numeric(14,2);
    v_system  numeric(14,2);
    v_open    integer;
    v_id      integer;
    v_when    timestamp;
BEGIN
    SELECT a.openingbalance INTO v_opening
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;

    IF v_opening IS NULL THEN
        RAISE EXCEPTION 'Cash account not found.';
    END IF;

    -- Belt to ux_poultrycashrecon_one_draft's braces, so the user gets a sentence
    -- rather than a unique-violation.
    SELECT h.poultrycashreconciliationid INTO v_open
    FROM   poultrycashreconciliations h
    WHERE  h.farmid = p_farmid AND h.poultrycashaccountid = p_poultrycashaccountid
      AND  h.status = 'Draft'
    LIMIT  1;

    IF v_open IS NOT NULL THEN
        RAISE EXCEPTION 'This account already has an open cash count (#%). Finish or delete it first.', v_open;
    END IF;

    SELECT v_opening + COALESCE(SUM(t.amount), 0) INTO v_system
    FROM   poultrycashtransactions t
    WHERE  t.farmid = p_farmid AND t.poultrycashaccountid = p_poultrycashaccountid;

    v_when := COALESCE(p_reconciliationdate, now() at time zone 'utc');

    INSERT INTO poultrycashreconciliations
        (farmid, poultrycashaccountid, reconciliationdate, systembalance,
         actualbalance, difference, reason, notes, status, createdby)
    VALUES
        (p_farmid, p_poultrycashaccountid, v_when, v_system,
         p_actualbalance,
         CASE WHEN p_actualbalance IS NULL THEN 0 ELSE ROUND(p_actualbalance - v_system, 2) END,
         p_reason, p_notes, 'Draft', p_createdby)
    RETURNING poultrycashreconciliationid INTO v_id;

    -- Human-quotable reference, same shape as sppoultryinternalusage_insert.
    UPDATE poultrycashreconciliations
    SET    referenceno = 'CC-' || to_char(v_when, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  poultrycashreconciliationid = v_id;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_update(
    p_poultrycashreconciliationid integer,
    p_farmid             text,
    p_reconciliationdate timestamp DEFAULT NULL,
    p_actualbalance      numeric   DEFAULT NULL,
    p_reason             text      DEFAULT NULL,
    p_notes              text      DEFAULT NULL,
    p_updatedby          text      DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_account integer;
    v_opening numeric(14,2);
    v_system  numeric(14,2);
BEGIN
    SELECT h.status, h.poultrycashaccountid INTO v_status, v_account
    FROM   poultrycashreconciliations h
    WHERE  h.poultrycashreconciliationid = p_poultrycashreconciliationid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Cash count % not found.', p_poultrycashreconciliationid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft cash count can be edited. This one is %. Start a new one.', v_status;
    END IF;

    -- Re-snapshot: cash may have moved since the draft was opened, and a stale
    -- expected figure on screen is how someone posts a difference that is not
    -- really there.
    SELECT a.openingbalance + COALESCE((SELECT SUM(t.amount) FROM poultrycashtransactions t
                                        WHERE t.farmid = p_farmid AND t.poultrycashaccountid = v_account), 0)
      INTO v_system
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = v_account AND a.farmid = p_farmid;

    UPDATE poultrycashreconciliations
    SET    reconciliationdate = COALESCE(p_reconciliationdate, reconciliationdate),
           systembalance      = v_system,
           actualbalance      = p_actualbalance,
           difference         = CASE WHEN p_actualbalance IS NULL THEN 0
                                     ELSE ROUND(p_actualbalance - v_system, 2) END,
           reason             = p_reason,
           notes              = p_notes,
           updatedat          = (now() at time zone 'utc')
    WHERE  poultrycashreconciliationid = p_poultrycashreconciliationid AND farmid = p_farmid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_delete(
    p_poultrycashreconciliationid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM poultrycashreconciliations h
    WHERE  h.poultrycashreconciliationid = p_poultrycashreconciliationid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN RETURN; END IF;      -- already gone: deleting is idempotent
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'A % cash count cannot be deleted -- reverse it instead, so the money history survives.', v_status;
    END IF;

    DELETE FROM poultrycashreconciliations
    WHERE poultrycashreconciliationid = p_poultrycashreconciliationid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Clearing status.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashtransaction_setclearing(
    p_farmid             text,
    p_poultrycashaccountid integer,
    p_transactionidsjson text,
    p_clearingstatus     text,
    p_clearingnotes      text DEFAULT NULL,
    p_userid             text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_locked text;
    v_n      integer := 0;
BEGIN
    IF p_clearingstatus NOT IN ('Uncleared', 'Cleared', 'Disputed') THEN
        RAISE EXCEPTION '% is not a clearing status.', p_clearingstatus;
    END IF;

    PERFORM 1 FROM poultrycashaccounts
    WHERE  poultrycashaccountid = p_poultrycashaccountid AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cash account not found.';
    END IF;

    IF p_transactionidsjson IS NULL OR btrim(p_transactionidsjson) IN ('', '[]') THEN
        RETURN 0;
    END IF;

    -- A row a POSTED count ticked off is part of that count's evidence. Letting
    -- it be un-ticked by hand would make the count's clearedcount a lie.
    SELECT COALESCE(h.referenceno, '#' || h.poultrycashreconciliationid::text) INTO v_locked
    FROM   poultrycashtransactions t
    JOIN   poultrycashreconciliations h
           ON h.poultrycashreconciliationid = t.poultrycashreconciliationid
    WHERE  t.farmid = p_farmid
      AND  t.poultrycashtransactionid IN (
               SELECT (json_array_elements_text(p_transactionidsjson::json))::integer)
      AND  h.status = 'Posted'
    LIMIT  1;

    IF v_locked IS NOT NULL THEN
        RAISE EXCEPTION 'One of those transactions was cleared by cash count %. Reverse that count to change it.', v_locked;
    END IF;

    UPDATE poultrycashtransactions t
    SET    clearingstatus = p_clearingstatus,
           cleareddate    = CASE WHEN p_clearingstatus = 'Cleared'
                                 THEN (now() at time zone 'utc') ELSE NULL END,
           clearedby      = CASE WHEN p_clearingstatus = 'Cleared' THEN p_userid ELSE NULL END,
           -- Clearing by hand has no parent count.
           poultrycashreconciliationid = NULL,
           clearingnotes  = NULLIF(btrim(COALESCE(p_clearingnotes, '')), '')
    WHERE  t.farmid = p_farmid
      AND  t.poultrycashaccountid = p_poultrycashaccountid
      AND  t.poultrycashtransactionid IN (
               SELECT (json_array_elements_text(p_transactionidsjson::json))::integer);

    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$function$;

-- Adoption helper: draw a line under history so the first count does not open
-- onto a thousand uncleared rows. Deliberately an explicit, attributable action
-- rather than something the migration does silently.
CREATE OR REPLACE FUNCTION public.sppoultrycashtransaction_clearbefore(
    p_farmid text, p_poultrycashaccountid integer, p_cutoff timestamp,
    p_note text DEFAULT NULL, p_userid text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE v_n integer;
BEGIN
    UPDATE poultrycashtransactions
    SET    clearingstatus = 'Cleared',
           cleareddate    = (now() at time zone 'utc'),
           clearedby      = p_userid,
           clearingnotes  = COALESCE(NULLIF(btrim(p_note), ''),
                                     'Opening cut-off: treated as cleared at adoption.')
    WHERE  farmid = p_farmid
      AND  poultrycashaccountid = p_poultrycashaccountid
      AND  transactiondate < p_cutoff
      AND  clearingstatus <> 'Cleared';

    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Post.
-- -----------------------------------------------------------------------------
-- Inlines its own ledger insert rather than calling sppoultrycashaccount_adjust.
-- That function writes SourceId = NULL (migration 129), so the delta rule below
-- and the adjustmenttransactionid linkage would have nothing to key on; it
-- returns nothing usable, so the linkage could not be captured anyway; it types
-- the row 'Adjustment', which would make a counted correction permanently
-- indistinguishable from someone typing -50 into the Adjust box; and its
-- Postgres body is not in this repo. Reuse buys no atomicity either -- a plpgsql
-- function called from another shares the caller's transaction regardless.
CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_post(
    p_poultrycashreconciliationid integer,
    p_farmid                    text,
    p_postedby                  text DEFAULT NULL,
    p_clearedtransactionidsjson text DEFAULT NULL)
RETURNS integer                       -- the adjustment txn id; NULL when balanced
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status    text;
    v_accountid integer;
    v_actual    numeric(14,2);
    v_when      timestamp;
    v_reason    text;
    v_ref       text;
    v_opening   numeric(14,2);
    v_cached    numeric(14,2);
    v_allowneg  boolean;
    v_true      numeric(14,2);
    v_diff      numeric(14,2);
    v_net       numeric(14,2);
    v_delta     numeric(14,2);
    v_adjid     integer;
    v_type      text;
    v_cleared   integer := 0;
    v_clearedamt numeric(14,2) := 0;
BEGIN
    SELECT h.status, h.poultrycashaccountid, h.actualbalance, h.reconciliationdate,
           h.reason, h.referenceno, h.adjustmenttransactionid
      INTO v_status, v_accountid, v_actual, v_when, v_reason, v_ref, v_adjid
    FROM   poultrycashreconciliations h
    WHERE  h.poultrycashreconciliationid = p_poultrycashreconciliationid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Cash count % not found.', p_poultrycashreconciliationid;
    END IF;
    -- Idempotent: a double-click cannot post twice. Paired with the delta
    -- arithmetic below, a repeat call is a genuine no-op.
    IF v_status = 'Posted' THEN RETURN v_adjid; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Cannot post a % cash count. Start a new one.', v_status;
    END IF;
    IF v_actual IS NULL THEN
        RAISE EXCEPTION 'Enter the amount you counted before posting.';
    END IF;

    -- Everything below is a read-modify-write of a denormalised balance, so the
    -- account row is locked for the duration.
    SELECT a.openingbalance, a.currentbalance, a.allownegativebalance
      INTO v_opening, v_cached, v_allowneg
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = v_accountid AND a.farmid = p_farmid
    FOR    UPDATE;

    IF v_opening IS NULL THEN
        RAISE EXCEPTION 'Cash account not found.';
    END IF;
    IF v_actual < 0 AND NOT COALESCE(v_allowneg, FALSE) THEN
        RAISE EXCEPTION 'A counted balance cannot be negative on this account.';
    END IF;

    -- Heal the cache BEFORE counting. currentbalance is a denormalised figure
    -- and migration 129's ReconcileBalance exists precisely because it drifts.
    -- Counting against a drifted cache posts a "difference" that is really a
    -- software bug, and blames the person holding the money. So: rebuild from
    -- the ledger, keep what the cache had said, then compute the real difference.
    SELECT v_opening + COALESCE(SUM(t.amount), 0) INTO v_true
    FROM   poultrycashtransactions t
    WHERE  t.farmid = p_farmid AND t.poultrycashaccountid = v_accountid;

    IF v_cached IS DISTINCT FROM v_true THEN
        UPDATE poultrycashaccounts
        SET    currentbalance = v_true, updatedat = (now() at time zone 'utc')
        WHERE  poultrycashaccountid = v_accountid AND farmid = p_farmid;
    END IF;

    v_diff := ROUND(v_actual - v_true, 2);       -- positive = over, negative = short

    -- Migration 179's delta rule, applied to money: work out the NET this count
    -- has already put in the ledger and post only the shortfall. Never delete,
    -- never rewrite.
    SELECT COALESCE(SUM(t.amount), 0) INTO v_net
    FROM   poultrycashtransactions t
    WHERE  t.farmid = p_farmid
      AND  t.sourcetype = 'ReconciliationAdjustment'
      AND  t.sourceid   = p_poultrycashreconciliationid;

    v_delta := v_diff - v_net;

    IF v_delta <> 0 THEN
        v_type := CASE WHEN v_delta > 0 THEN 'AdjustmentIn' ELSE 'AdjustmentOut' END;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat, createdat,
             clearingstatus, cleareddate, clearedby, poultrycashreconciliationid)
        VALUES
            (p_farmid, v_accountid, COALESCE(v_when, now() at time zone 'utc'), v_type,
             'ReconciliationAdjustment', p_poultrycashreconciliationid,
             v_delta, v_true + v_delta,
             'Cash count ' || COALESCE(v_ref, '#' || p_poultrycashreconciliationid::text)
                 || CASE WHEN v_delta > 0 THEN ' (over)' ELSE ' (short)' END
                 || COALESCE(' - ' || NULLIF(btrim(v_reason), ''), ''),
             p_postedby, p_postedby, (now() at time zone 'utc'), (now() at time zone 'utc'),
             -- The correction is cleared by definition: it IS what makes the
             -- count true. Carrying its own id keeps the reversal sweep exact.
             'Cleared', (now() at time zone 'utc'), p_postedby, p_poultrycashreconciliationid)
        RETURNING poultrycashtransactionid INTO v_adjid;

        UPDATE poultrycashaccounts
        SET    currentbalance = currentbalance + v_delta,
               updatedat = (now() at time zone 'utc')
        WHERE  poultrycashaccountid = v_accountid AND farmid = p_farmid;
    END IF;

    -- Tick off what the counter agreed with. Scoped to this farm AND this
    -- account; a row another count already cleared is left alone.
    IF p_clearedtransactionidsjson IS NOT NULL
       AND btrim(p_clearedtransactionidsjson) NOT IN ('', '[]') THEN
        WITH ids AS (
            SELECT (json_array_elements_text(p_clearedtransactionidsjson::json))::integer AS id
        ), upd AS (
            UPDATE poultrycashtransactions t
            SET    clearingstatus = 'Cleared',
                   cleareddate    = (now() at time zone 'utc'),
                   clearedby      = p_postedby,
                   poultrycashreconciliationid = p_poultrycashreconciliationid
            FROM   ids
            WHERE  t.poultrycashtransactionid = ids.id
              AND  t.farmid = p_farmid
              AND  t.poultrycashaccountid = v_accountid
              AND  COALESCE(t.clearingstatus, 'Uncleared') <> 'Cleared'
            RETURNING t.amount
        )
        SELECT count(*)::integer, COALESCE(SUM(amount), 0) INTO v_cleared, v_clearedamt FROM upd;
    END IF;

    UPDATE poultrycashreconciliations
    SET    status = 'Posted',
           systembalance = v_true,
           systembalancecached = v_cached,
           difference = v_diff,
           adjustmenttransactionid = COALESCE(v_adjid, adjustmenttransactionid),
           clearedcount = v_cleared,
           clearedamount = v_clearedamt,
           postedby = p_postedby,
           postedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc')
    WHERE  poultrycashreconciliationid = p_poultrycashreconciliationid AND farmid = p_farmid;

    UPDATE poultrycashaccounts
    SET    lastreconciledat = COALESCE(v_when, now() at time zone 'utc'),
           lastreconciledbalance = v_actual,
           updatedat = (now() at time zone 'utc')
    WHERE  poultrycashaccountid = v_accountid AND farmid = p_farmid;

    RETURN v_adjid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Reverse.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_reverse(
    p_poultrycashreconciliationid integer,
    p_farmid     text,
    p_reason     text DEFAULT NULL,
    p_reversedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status    text;
    v_accountid integer;
    v_ref       text;
    v_net       numeric(14,2);
    v_delta     numeric(14,2);
    v_revid     integer;
    v_prevat    timestamp;
    v_prevbal   numeric(14,2);
BEGIN
    SELECT h.status, h.poultrycashaccountid, h.referenceno
      INTO v_status, v_accountid, v_ref
    FROM   poultrycashreconciliations h
    WHERE  h.poultrycashreconciliationid = p_poultrycashreconciliationid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Cash count % not found.', p_poultrycashreconciliationid;
    END IF;
    IF v_status = 'Reversed' THEN RETURN; END IF;          -- idempotent
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted cash count can be reversed. This one is %.', v_status;
    END IF;

    PERFORM 1 FROM poultrycashaccounts
    WHERE  poultrycashaccountid = v_accountid AND farmid = p_farmid
    FOR    UPDATE;

    -- Same delta rule as post, target 0: put back exactly what this count moved,
    -- as a NEW row. The original stays, so the ledger tells the whole story.
    SELECT COALESCE(SUM(t.amount), 0) INTO v_net
    FROM   poultrycashtransactions t
    WHERE  t.farmid = p_farmid
      AND  t.sourcetype = 'ReconciliationAdjustment'
      AND  t.sourceid   = p_poultrycashreconciliationid;

    v_delta := 0 - v_net;

    IF v_delta <> 0 THEN
        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat, createdat,
             clearingstatus, cleareddate, clearedby, poultrycashreconciliationid, clearingnotes)
        SELECT p_farmid, v_accountid, (now() at time zone 'utc'),
               CASE WHEN v_delta > 0 THEN 'AdjustmentIn' ELSE 'AdjustmentOut' END,
               'ReconciliationAdjustment', p_poultrycashreconciliationid,
               v_delta, a.currentbalance + v_delta,
               'Reversal of cash count ' || COALESCE(v_ref, '#' || p_poultrycashreconciliationid::text)
                   || COALESCE(': ' || NULLIF(btrim(p_reason), ''), ''),
               p_reversedby, p_reversedby, (now() at time zone 'utc'), (now() at time zone 'utc'),
               'Cleared', (now() at time zone 'utc'), p_reversedby,
               p_poultrycashreconciliationid, 'Nets the posted correction to zero.'
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = v_accountid AND a.farmid = p_farmid
        RETURNING poultrycashtransactionid INTO v_revid;

        UPDATE poultrycashaccounts
        SET    currentbalance = currentbalance + v_delta,
               updatedat = (now() at time zone 'utc')
        WHERE  poultrycashaccountid = v_accountid AND farmid = p_farmid;
    END IF;

    -- Un-tick what THIS count cleared, and nothing else. A row a LATER count
    -- cleared carries that count's id; a row cleared by hand carries none. Both
    -- are untouched. The count's own adjustment pair keeps its Cleared flag --
    -- the two rows net to zero and must not clutter the uncleared list forever.
    UPDATE poultrycashtransactions
    SET    clearingstatus = 'Uncleared',
           cleareddate = NULL,
           clearedby = NULL,
           poultrycashreconciliationid = NULL,
           clearingnotes = COALESCE(NULLIF(clearingnotes, '') || ' | ', '')
                           || 'Un-cleared when cash count '
                           || COALESCE(v_ref, '#' || p_poultrycashreconciliationid::text)
                           || ' was reversed.'
    WHERE  farmid = p_farmid
      AND  poultrycashaccountid = v_accountid
      AND  poultrycashreconciliationid = p_poultrycashreconciliationid
      AND  COALESCE(sourcetype, '') <> 'ReconciliationAdjustment';

    UPDATE poultrycashreconciliations
    SET    status = 'Reversed',
           reversaltransactionid = COALESCE(v_revid, reversaltransactionid),
           reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'),
           reversalreason = p_reason,
           updatedat = (now() at time zone 'utc')
    WHERE  poultrycashreconciliationid = p_poultrycashreconciliationid AND farmid = p_farmid;

    -- Roll the marker back to the most recent count that is STILL posted, or
    -- clear it if this was the only one. Blanking it unconditionally would erase
    -- a perfectly good earlier count. The status UPDATE above runs first, so
    -- "status = 'Posted'" already excludes the one being reversed.
    SELECT h.reconciliationdate, h.actualbalance INTO v_prevat, v_prevbal
    FROM   poultrycashreconciliations h
    WHERE  h.farmid = p_farmid AND h.poultrycashaccountid = v_accountid AND h.status = 'Posted'
    ORDER  BY h.reconciliationdate DESC, h.poultrycashreconciliationid DESC
    LIMIT  1;

    UPDATE poultrycashaccounts
    SET    lastreconciledat = v_prevat,
           lastreconciledbalance = v_prevbal,
           updatedat = (now() at time zone 'utc')
    WHERE  poultrycashaccountid = v_accountid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Reads.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_getall(
    p_farmid             text,
    p_poultrycashaccountid integer   DEFAULT NULL,
    p_status             text      DEFAULT NULL,
    p_fromdate           timestamp DEFAULT NULL,
    p_todate             timestamp DEFAULT NULL)
RETURNS TABLE (
    poultrycashreconciliationid integer, farmid text, poultrycashaccountid integer,
    accountname text, accounttype text, referenceno text, reconciliationdate timestamp,
    systembalance numeric, systembalancecached numeric, actualbalance numeric,
    difference numeric, adjustmenttransactionid integer, reversaltransactionid integer,
    clearedcount integer, clearedamount numeric, reason text, notes text, status text,
    createdby text, createdat timestamp, updatedat timestamp,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text)
LANGUAGE sql
STABLE
AS $$
    SELECT h.poultrycashreconciliationid, h.farmid, h.poultrycashaccountid,
           a.accountname, a.accounttype, h.referenceno, h.reconciliationdate,
           h.systembalance, h.systembalancecached, h.actualbalance,
           h.difference, h.adjustmenttransactionid, h.reversaltransactionid,
           h.clearedcount, h.clearedamount, h.reason, h.notes, h.status,
           h.createdby, h.createdat, h.updatedat,
           h.postedby, h.postedat, h.reversedby, h.reversedat, h.reversalreason
    FROM   poultrycashreconciliations h
    JOIN   poultrycashaccounts a ON a.poultrycashaccountid = h.poultrycashaccountid
    WHERE  h.farmid = p_farmid
      AND  (p_poultrycashaccountid IS NULL OR h.poultrycashaccountid = p_poultrycashaccountid)
      AND  (p_status   IS NULL OR h.status = p_status)
      AND  (p_fromdate IS NULL OR h.reconciliationdate >= p_fromdate)
      AND  (p_todate   IS NULL OR h.reconciliationdate <= p_todate)
    ORDER  BY h.reconciliationdate DESC, h.poultrycashreconciliationid DESC;
$$;

-- One canonical shape, one place to change it.
CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_getbyid(
    p_poultrycashreconciliationid integer, p_farmid text)
RETURNS TABLE (
    poultrycashreconciliationid integer, farmid text, poultrycashaccountid integer,
    accountname text, accounttype text, referenceno text, reconciliationdate timestamp,
    systembalance numeric, systembalancecached numeric, actualbalance numeric,
    difference numeric, adjustmenttransactionid integer, reversaltransactionid integer,
    clearedcount integer, clearedamount numeric, reason text, notes text, status text,
    createdby text, createdat timestamp, updatedat timestamp,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text)
LANGUAGE sql
STABLE
AS $$
    -- Aliased: the function's own OUT column is also called
    -- poultrycashreconciliationid, so an unqualified WHERE would be ambiguous.
    SELECT r.* FROM public.sppoultrycashreconciliation_getall(p_farmid) r
    WHERE  r.poultrycashreconciliationid = p_poultrycashreconciliationid;
$$;

CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_getbyaccount(
    p_poultrycashaccountid integer, p_farmid text)
RETURNS TABLE (
    poultrycashreconciliationid integer, farmid text, poultrycashaccountid integer,
    accountname text, accounttype text, referenceno text, reconciliationdate timestamp,
    systembalance numeric, systembalancecached numeric, actualbalance numeric,
    difference numeric, adjustmenttransactionid integer, reversaltransactionid integer,
    clearedcount integer, clearedamount numeric, reason text, notes text, status text,
    createdby text, createdat timestamp, updatedat timestamp,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text)
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM public.sppoultrycashreconciliation_getall(p_farmid, p_poultrycashaccountid);
$$;

-- The ledger read WITH clearing. A new function rather than an edit to
-- sppoultrycashtransaction_getbyfarm, because that function's Postgres body is not
-- in this repo and CREATE OR REPLACE cannot change a RETURNS TABLE column list.
-- The first 15 columns match it exactly (129:223) so callers can move over
-- without remapping.
CREATE OR REPLACE FUNCTION public.sppoultrycashtransaction_getledger(
    p_farmid                    text,
    p_poultrycashaccountid        integer   DEFAULT NULL,
    p_fromdate                  timestamp DEFAULT NULL,
    p_todate                    timestamp DEFAULT NULL,
    p_clearingstatus            text      DEFAULT NULL,
    p_poultrycashreconciliationid integer   DEFAULT NULL)
RETURNS TABLE (
    poultrycashtransactionid integer, farmid text, poultrycashaccountid integer,
    accountname text, transactiondate timestamp, transactiontype text,
    sourcetype text, sourceid integer, amount numeric,
    balanceaftertransaction numeric, description text,
    createdby text, approvedby text, approvedat timestamp, createdat timestamp,
    clearingstatus text, cleareddate timestamp, clearedby text,
    poultrycashreconciliationid integer, clearingnotes text,
    reconciliationreference text)
LANGUAGE sql
STABLE
AS $$
    SELECT t.poultrycashtransactionid, t.farmid, t.poultrycashaccountid, a.accountname,
           t.transactiondate, t.transactiontype, t.sourcetype, t.sourceid,
           t.amount, t.balanceaftertransaction, t.description,
           t.createdby, t.approvedby, t.approvedat, t.createdat,
           COALESCE(t.clearingstatus, 'Uncleared'), t.cleareddate, t.clearedby,
           t.poultrycashreconciliationid, t.clearingnotes,
           h.referenceno
    FROM   poultrycashtransactions t
    JOIN   poultrycashaccounts a ON a.poultrycashaccountid = t.poultrycashaccountid
    LEFT   JOIN poultrycashreconciliations h
           ON h.poultrycashreconciliationid = t.poultrycashreconciliationid
    WHERE  t.farmid = p_farmid
      AND  (p_poultrycashaccountid IS NULL OR t.poultrycashaccountid = p_poultrycashaccountid)
      AND  (p_fromdate IS NULL OR t.transactiondate >= p_fromdate)
      AND  (p_todate   IS NULL OR t.transactiondate <= p_todate)
      AND  (p_clearingstatus IS NULL OR COALESCE(t.clearingstatus, 'Uncleared') = p_clearingstatus)
      AND  (p_poultrycashreconciliationid IS NULL
            OR t.poultrycashreconciliationid = p_poultrycashreconciliationid)
    ORDER  BY t.transactiondate DESC, t.poultrycashtransactionid DESC;
$$;

-- Badge feed for the accounts list: how stale is each account's last count, how
-- much is still unticked, and has the cache drifted. Additive, so
-- sppoultrycashaccount_getall stays untouched.
CREATE OR REPLACE FUNCTION public.sppoultrycashreconciliation_getaccountstatus(p_farmid text)
RETURNS TABLE (
    poultrycashaccountid integer, accountname text, accounttype text, isactive boolean,
    currentbalance numeric, ledgerbalance numeric, cachedrift numeric,
    lastreconciledat timestamp, lastreconciledbalance numeric,
    dayssincereconciled integer, unclearedcount bigint, unclearedamount numeric,
    opendraftid integer)
LANGUAGE sql
STABLE
AS $$
    SELECT a.poultrycashaccountid, a.accountname, a.accounttype, a.isactive,
           a.currentbalance,
           a.openingbalance + COALESCE(l.total, 0),
           ROUND(a.currentbalance - (a.openingbalance + COALESCE(l.total, 0)), 2),
           a.lastreconciledat, a.lastreconciledbalance,
           CASE WHEN a.lastreconciledat IS NULL THEN NULL
                ELSE EXTRACT(DAY FROM (now() at time zone 'utc') - a.lastreconciledat)::integer
           END,
           COALESCE(u.n, 0), COALESCE(u.amt, 0),
           d.poultrycashreconciliationid
    FROM   poultrycashaccounts a
    LEFT   JOIN LATERAL (
        SELECT SUM(t.amount) AS total
        FROM   poultrycashtransactions t
        WHERE  t.farmid = a.farmid AND t.poultrycashaccountid = a.poultrycashaccountid
    ) l ON TRUE
    LEFT   JOIN LATERAL (
        SELECT count(*) AS n, SUM(t.amount) AS amt
        FROM   poultrycashtransactions t
        WHERE  t.farmid = a.farmid AND t.poultrycashaccountid = a.poultrycashaccountid
          AND  COALESCE(t.clearingstatus, 'Uncleared') <> 'Cleared'
    ) u ON TRUE
    LEFT   JOIN LATERAL (
        SELECT h.poultrycashreconciliationid
        FROM   poultrycashreconciliations h
        WHERE  h.farmid = a.farmid AND h.poultrycashaccountid = a.poultrycashaccountid
          AND  h.status = 'Draft'
        LIMIT  1
    ) d ON TRUE
    WHERE  a.farmid = p_farmid
    ORDER  BY a.accountname;
$$;

-- -----------------------------------------------------------------------------
-- 9. IAM catalog.
-- -----------------------------------------------------------------------------
-- A new resource, not an extra action on *.cash: migration 199 seeds cash with
-- view,create,edit,delete,export and no approve, and widening a shared resource
-- would silently grant reconciliation rights to everyone who can see cash.
DO $iam$
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '223: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.cash-reconciliation.' || a.action, 'poultry', 'cash-reconciliation', a.action,
           'Finance', 'Cash Reconciliation',
           'Count a cash account and post the difference. Delete covers reversing a posted count.',
           'Poultry', a.action = 'delete', 83
    FROM   (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'reconciliation table' AS check,
       CASE WHEN to_regclass('public.poultrycashreconciliations') IS NOT NULL
            THEN 'OK' ELSE 'MISSING' END AS result
UNION ALL
SELECT 'clearing columns (5 expected)',
       CASE WHEN count(*) = 5 THEN 'OK' ELSE 'MISSING (' || count(*) || ')' END
FROM   information_schema.columns
WHERE  table_name = 'poultrycashtransactions'
  AND  column_name IN ('clearingstatus','cleareddate','clearedby',
                       'poultrycashreconciliationid','clearingnotes')
UNION ALL
SELECT 'account marker columns (2 expected)',
       CASE WHEN count(*) = 2 THEN 'OK' ELSE 'MISSING (' || count(*) || ')' END
FROM   information_schema.columns
WHERE  table_name = 'poultrycashaccounts'
  AND  column_name IN ('lastreconciledat','lastreconciledbalance')
UNION ALL
SELECT 'functions (12 expected)',
       CASE WHEN count(*) = 12 THEN 'OK' ELSE 'ONLY ' || count(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sppoultrycashreconciliation_insert','sppoultrycashreconciliation_update',
                     'sppoultrycashreconciliation_delete','sppoultrycashreconciliation_post',
                     'sppoultrycashreconciliation_reverse','sppoultrycashreconciliation_getall',
                     'sppoultrycashreconciliation_getbyid','sppoultrycashreconciliation_getbyaccount',
                     'sppoultrycashreconciliation_getaccountstatus','sppoultrycashtransaction_getledger',
                     'sppoultrycashtransaction_setclearing','sppoultrycashtransaction_clearbefore')
UNION ALL
SELECT 'no NULL clearing status',
       CASE WHEN NOT EXISTS (SELECT 1 FROM poultrycashtransactions WHERE clearingstatus IS NULL)
            THEN 'OK' ELSE 'BAD' END
UNION ALL
-- Pre-existing drift is expected and is NOT a failure of this migration; _post
-- heals the account it touches. Run POST /Poultry/cash-accounts/reconcile-balances
-- once per farm before rollout to clear it everywhere.
SELECT 'balance identity (drift is pre-existing)',
       CASE WHEN NOT EXISTS (
              SELECT 1 FROM poultrycashaccounts a
              WHERE  a.currentbalance <> a.openingbalance
                   + COALESCE((SELECT SUM(t.amount) FROM poultrycashtransactions t
                               WHERE t.poultrycashaccountid = a.poultrycashaccountid
                                 AND t.farmid = a.farmid), 0))
            THEN 'OK' ELSE 'DRIFT PRESENT - run reconcile-balances' END;

-- Which accounts have drifted, if any.
SELECT a.farmid, a.poultrycashaccountid, a.accountname,
       a.currentbalance AS cached,
       a.openingbalance + COALESCE((SELECT SUM(t.amount) FROM poultrycashtransactions t
                                    WHERE t.poultrycashaccountid = a.poultrycashaccountid
                                      AND t.farmid = a.farmid), 0) AS ledger
FROM   poultrycashaccounts a
WHERE  a.currentbalance <> a.openingbalance
     + COALESCE((SELECT SUM(t.amount) FROM poultrycashtransactions t
                 WHERE t.poultrycashaccountid = a.poultrycashaccountid
                   AND t.farmid = a.farmid), 0);

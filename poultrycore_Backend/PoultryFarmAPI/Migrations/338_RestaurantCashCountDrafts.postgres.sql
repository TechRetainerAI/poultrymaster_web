-- =============================================================================
-- 338_RestaurantCashCountDrafts.postgres.sql
--
-- Restaurant cash counts learn Poultry's (223) / Hotel's (331) two-step flow:
-- Draft -> Post -> (Reverse). Today sprestaurant_cashcount_post (323, ~1118)
-- creates the row AND posts the variance in one call, so "Record a count"
-- moves money immediately. That stays exactly as it was -- nothing calls it
-- from the new flow, but it is not dropped in case something else still does.
--
-- New flow, same table, no new column (restaurantcashcounts is read with
-- SELECT * / by ordinal elsewhere -- see 323's header):
--   sprestaurant_cashcount_savedraft   creates a Draft row. No money moves.
--   sprestaurant_cashcount_updatedraft edits countedbalance/notes on a Draft.
--   sprestaurant_cashcount_discard     deletes a Draft. Refused on anything else
--                                      (reverse a posted count instead, so the
--                                      money history survives -- Hotel's wording).
--   sprestaurant_cashcount_postdraft   the ONLY place money moves for this flow:
--                                      heals the cached balance from the ledger,
--                                      measures the difference against THAT
--                                      (never the draft's stale snapshot), and
--                                      posts it through fnrestaurant_post exactly
--                                      as sprestaurant_cashcount_post always did
--                                      -- same sourcetype/sourceid ('CountVariance',
--                                      countid), so a retried post is a no-op
--                                      (status is already 'Posted') and the
--                                      ux_restaurantcashtxn_source unique index
--                                      backstops it. fnrestaurant_assert_day_open
--                                      is only called here: a draft moves no
--                                      cash, so it needs no open-day check.
--
-- One open draft per account (ux_restaurantcashcounts_one_draft, Poultry/Hotel's
-- rule): a second sprestaurant_cashcount_savedraft on the same account is
-- refused with a friendly message pointing at the existing draft, and the
-- constraint backstops it under concurrency.
--
-- Till shift cash-ups (sprestaurant_cashshift_close, 323 ~650) never touch
-- restaurantcashcounts at all -- they post ShiftVariance straight to the
-- ledger -- so they are untouched here and stay posted immediately, as asked.
--
-- Re-runnable: the CHECK is dropped and re-added by its conventional name,
-- the unique index is IF NOT EXISTS, and every function this migration adds
-- is dropped by signature first.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Drop the four functions this migration (re)defines, all overloads.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('sprestaurant_cashcount_savedraft', 'sprestaurant_cashcount_updatedraft',
                            'sprestaurant_cashcount_discard', 'sprestaurant_cashcount_postdraft')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Widen the status CHECK: 'Draft' joins 'Posted' / 'Reversed'.
-- -----------------------------------------------------------------------------
ALTER TABLE restaurantcashcounts DROP CONSTRAINT IF EXISTS restaurantcashcounts_status_check;
ALTER TABLE restaurantcashcounts ADD CONSTRAINT restaurantcashcounts_status_check
    CHECK (status IN ('Draft', 'Posted', 'Reversed'));

-- Only one open draft per account, same rule as Poultry (223) and Hotel (331).
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantcashcounts_one_draft
    ON restaurantcashcounts (farmid, cashaccountid) WHERE status = 'Draft';

-- -----------------------------------------------------------------------------
-- 2. Save a draft. Moves no money -- the systembalance/difference stored here
--    are a snapshot for display; sprestaurant_cashcount_postdraft re-measures
--    against the ledger when it actually posts.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_cashcount_savedraft(p_farmid TEXT, p_cashaccountid INT, p_counted NUMERIC DEFAULT NULL,
                                                 p_notes TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_acc restaurantcashaccounts%ROWTYPE; v_id INT; v_open INT; v_ledger NUMERIC;
        v_counted NUMERIC := ROUND(COALESCE(p_counted, -1), 2);
BEGIN
    SELECT * INTO v_acc FROM restaurantcashaccounts WHERE cashaccountid = p_cashaccountid AND farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash account not found.'; END IF;
    IF v_counted < 0 THEN RAISE EXCEPTION 'Enter the balance you counted or confirmed.'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashshifts s WHERE s.cashaccountid = p_cashaccountid AND s.status = 'Open') THEN
        RAISE EXCEPTION '"%" has an open shift. Count it by closing the shift.', v_acc.name;
    END IF;

    SELECT h.countid INTO v_open FROM restaurantcashcounts h
     WHERE h.farmid = p_farmid AND h.cashaccountid = p_cashaccountid AND h.status = 'Draft' LIMIT 1;
    IF v_open IS NOT NULL THEN
        RAISE EXCEPTION 'This account already has an open draft count (#%). Post, edit or discard it first.', v_open;
    END IF;

    -- Heal the cached balance from the ledger, same as sprestaurant_cashcount_post.
    SELECT COALESCE(SUM(t.amount), 0) INTO v_ledger FROM restaurantcashtransactions t WHERE t.cashaccountid = p_cashaccountid;
    IF v_ledger <> v_acc.currentbalance THEN
        UPDATE restaurantcashaccounts SET currentbalance = v_ledger WHERE cashaccountid = p_cashaccountid;
    END IF;

    INSERT INTO restaurantcashcounts (farmid, cashaccountid, countdate, systembalance, countedbalance, difference,
                                      status, notes, createdby)
    VALUES (p_farmid, p_cashaccountid, CURRENT_DATE, v_ledger, v_counted, ROUND(v_counted - v_ledger, 2),
            'Draft', NULLIF(btrim(COALESCE(p_notes, '')), ''), p_createdby)
    RETURNING countid INTO v_id;
    RETURN v_id;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Edit a draft. Refused once it is Posted or Reversed -- correct THAT by
--    reversing it instead, so the money history survives (Hotel's wording).
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_cashcount_updatedraft(p_farmid TEXT, p_id INT, p_counted NUMERIC DEFAULT NULL,
                                                   p_notes TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_c restaurantcashcounts%ROWTYPE; v_ledger NUMERIC;
        v_counted NUMERIC := ROUND(COALESCE(p_counted, -1), 2);
BEGIN
    SELECT * INTO v_c FROM restaurantcashcounts WHERE countid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Count not found.'; END IF;
    IF v_c.status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft cash count can be edited. This one is %. Start a new one.', v_c.status;
    END IF;
    IF v_counted < 0 THEN RAISE EXCEPTION 'Enter the balance you counted or confirmed.'; END IF;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_ledger FROM restaurantcashtransactions t WHERE t.cashaccountid = v_c.cashaccountid;

    UPDATE restaurantcashcounts
       SET systembalance = v_ledger, countedbalance = v_counted, difference = ROUND(v_counted - v_ledger, 2),
           notes = NULLIF(btrim(COALESCE(p_notes, '')), '')
     WHERE countid = p_id;
END $$;

-- -----------------------------------------------------------------------------
-- 4. Discard a draft. A draft moved no money, so this is a plain delete; a
--    posted or reversed count is left alone -- point the caller at Reverse.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_cashcount_discard(p_farmid TEXT, p_id INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT h.status INTO v_status FROM restaurantcashcounts h WHERE h.countid = p_id AND h.farmid = p_farmid;
    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'A % cash count cannot be discarded -- reverse it instead, so the money history survives.', v_status;
    END IF;
    DELETE FROM restaurantcashcounts WHERE countid = p_id AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 5. Post a draft. THE only place money moves for this flow -- everything
--    below mirrors sprestaurant_cashcount_post (323, ~1118) exactly: heal the
--    cache from the ledger, measure the difference against that, post it
--    through fnrestaurant_post with the same 'CountVariance'/countid pair
--    (so ux_restaurantcashtxn_source makes a retry harmless), then stamp
--    lastcountedat/lastcountedbalance. Idempotent: a count already Posted
--    just returns its id again rather than posting a second time.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_cashcount_postdraft(p_farmid TEXT, p_id INT, p_postedby TEXT DEFAULT NULL)
RETURNS TABLE(countid INT, adjustmenttransactionid INT) LANGUAGE plpgsql AS $$
DECLARE v_c restaurantcashcounts%ROWTYPE; v_acc restaurantcashaccounts%ROWTYPE;
        v_sys NUMERIC; v_diff NUMERIC; v_txn INT;
BEGIN
    SELECT * INTO v_c FROM restaurantcashcounts WHERE restaurantcashcounts.countid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Count not found.'; END IF;
    IF v_c.status = 'Posted' THEN RETURN QUERY SELECT v_c.countid, NULL::INT; RETURN; END IF;
    IF v_c.status <> 'Draft' THEN RAISE EXCEPTION 'Cannot post a % cash count. Start a new one.', v_c.status; END IF;

    SELECT * INTO v_acc FROM restaurantcashaccounts WHERE cashaccountid = v_c.cashaccountid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash account not found.'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashshifts s WHERE s.cashaccountid = v_c.cashaccountid AND s.status = 'Open') THEN
        RAISE EXCEPTION '"%" has an open shift. Count it by closing the shift.', v_acc.name;
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    SELECT COALESCE(SUM(t.amount), 0) INTO v_sys FROM restaurantcashtransactions t WHERE t.cashaccountid = v_c.cashaccountid;
    IF v_sys <> v_acc.currentbalance THEN
        UPDATE restaurantcashaccounts SET currentbalance = v_sys WHERE cashaccountid = v_c.cashaccountid;
    END IF;
    v_diff := ROUND(v_c.countedbalance - v_sys, 2);

    IF v_diff <> 0 THEN
        v_txn := fnrestaurant_post(p_farmid, v_c.cashaccountid, CURRENT_DATE, v_diff, 'CountVariance', p_id,
                                   CASE WHEN v_diff > 0 THEN 'Count found more than recorded in ' ELSE 'Count found less than recorded in ' END
                                   || v_acc.name, p_postedby);
    END IF;

    UPDATE restaurantcashcounts
       SET status = 'Posted', systembalance = v_sys, difference = v_diff
     WHERE restaurantcashcounts.countid = p_id;
    UPDATE restaurantcashaccounts SET lastcountedat = NOW(), lastcountedbalance = v_c.countedbalance
     WHERE cashaccountid = v_c.cashaccountid;

    RETURN QUERY SELECT p_id, v_txn;
END $$;

-- -----------------------------------------------------------------------------
-- Verification (read-only)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                    WHERE t.relname = 'restaurantcashcounts' AND c.conname = 'restaurantcashcounts_status_check'
                      AND pg_get_constraintdef(c.oid) ILIKE '%Draft%') THEN
        RAISE EXCEPTION '338 verification failed: status CHECK does not allow Draft';
    END IF;
    IF to_regprocedure('sprestaurant_cashcount_savedraft(text,integer,numeric,text,text)') IS NULL
       OR to_regprocedure('sprestaurant_cashcount_updatedraft(text,integer,numeric,text)') IS NULL
       OR to_regprocedure('sprestaurant_cashcount_discard(text,integer)') IS NULL
       OR to_regprocedure('sprestaurant_cashcount_postdraft(text,integer,text)') IS NULL THEN
        RAISE EXCEPTION '338 verification failed: a draft function is missing';
    END IF;
END $$;

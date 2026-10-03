-- Self-test for migration 338 (Restaurant cash count drafts). Always ends by
-- raising so everything rolls back; "SELFTEST PASSED" is the success signal.
--
-- Proves: a draft moves no cash and blocks a second draft on the same
-- account; posting it moves the variance exactly once, even if post is
-- retried (idempotent, backstopped by ux_restaurantcashtxn_source); a posted
-- count refuses both discard and edit; a genuine draft discards cleanly with
-- no ledger row, freeing the account for a new one; a balanced count still
-- posts (no adjustment row needed) and is marked Posted.
DO $$
DECLARE
    f TEXT := '__probe338__';
    v_cash INT; v_c1 INT; v_c2 INT; v_c3 INT;
    v_n NUMERIC; v_i INT; v_failed BOOLEAN; v_checks INT := 0; v_adj INT;
BEGIN
    v_cash := sprestaurant_cashaccount_create(f, 'Probe Safe', 'CashBox', 500, TRUE, NULL, NULL, 'probe');

    -- 1. Save a draft: no cash moves.
    v_c1 := sprestaurant_cashcount_savedraft(f, v_cash, 550, 'over by fifty', 'probe');
    IF (SELECT status FROM restaurantcashcounts WHERE countid = v_c1) <> 'Draft' THEN RAISE EXCEPTION 'FAIL 1: not a draft'; END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> 500 THEN
        RAISE EXCEPTION 'FAIL 1b: draft moved the balance'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashtransactions WHERE farmid = f AND sourcetype = 'CountVariance') THEN
        RAISE EXCEPTION 'FAIL 1c: draft posted to the ledger'; END IF;
    v_checks := v_checks + 3;

    -- 2. One open draft per account is refused (ux_restaurantcashcounts_one_draft).
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_cashcount_savedraft(f, v_cash, 500, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%already has an open draft count%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2: a second draft was allowed'; END IF;
    v_checks := v_checks + 1;

    -- 3. Edit the draft.
    PERFORM sprestaurant_cashcount_updatedraft(f, v_c1, 560, 'over by sixty');
    IF (SELECT countedbalance FROM restaurantcashcounts WHERE countid = v_c1) <> 560 THEN RAISE EXCEPTION 'FAIL 3: edit did not stick'; END IF;
    v_checks := v_checks + 1;

    -- 4. Post: the variance moves through fnrestaurant_post exactly as
    --    sprestaurant_cashcount_post always did.
    SELECT adjustmenttransactionid INTO v_adj FROM sprestaurant_cashcount_postdraft(f, v_c1, 'probe');
    IF (SELECT status FROM restaurantcashcounts WHERE countid = v_c1) <> 'Posted' THEN RAISE EXCEPTION 'FAIL 4: not posted'; END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> 560 THEN
        RAISE EXCEPTION 'FAIL 4b: balance after post %', (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash); END IF;
    SELECT COUNT(*), SUM(amount) INTO v_i, v_n FROM restaurantcashtransactions
     WHERE farmid = f AND sourcetype = 'CountVariance' AND sourceid = v_c1;
    IF v_i <> 1 OR v_n <> 60 THEN RAISE EXCEPTION 'FAIL 4c: ledger rows % sum % (want 1, 60)', v_i, v_n; END IF;
    IF v_adj IS NULL THEN RAISE EXCEPTION 'FAIL 4d: no adjustment id returned'; END IF;
    v_checks := v_checks + 4;

    -- 5. Posting again is a no-op: status is already Posted, so it returns
    --    early without a second ledger row (ux_restaurantcashtxn_source backstops it).
    v_adj := NULL;
    SELECT adjustmenttransactionid INTO v_adj FROM sprestaurant_cashcount_postdraft(f, v_c1, 'probe');
    IF v_adj IS NOT NULL THEN RAISE EXCEPTION 'FAIL 5: reposted and returned a new adjustment'; END IF;
    SELECT COUNT(*) INTO v_i FROM restaurantcashtransactions WHERE farmid = f AND sourcetype = 'CountVariance' AND sourceid = v_c1;
    IF v_i <> 1 THEN RAISE EXCEPTION 'FAIL 5b: a retry posted a second row'; END IF;
    v_checks := v_checks + 2;

    -- 6. A posted count refuses both discard and edit -- reverse it instead.
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_cashcount_discard(f, v_c1);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%cannot be discarded%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6: discarded a posted count'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_cashcount_updatedraft(f, v_c1, 600, NULL);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%Only a draft%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6b: edited a posted count'; END IF;
    v_checks := v_checks + 2;

    -- 7. A genuine draft discards cleanly with no ledger row, freeing the
    --    account; and a balanced count still posts (no adjustment needed).
    v_c2 := sprestaurant_cashcount_savedraft(f, v_cash, 999, NULL, 'probe');
    PERFORM sprestaurant_cashcount_discard(f, v_c2);
    IF EXISTS (SELECT 1 FROM restaurantcashcounts WHERE countid = v_c2) THEN RAISE EXCEPTION 'FAIL 7: discard left a row behind'; END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> 560 THEN
        RAISE EXCEPTION 'FAIL 7b: discard moved money'; END IF;
    v_c3 := sprestaurant_cashcount_savedraft(f, v_cash, 560, NULL, 'probe');   -- balances exactly
    v_adj := NULL;
    SELECT adjustmenttransactionid INTO v_adj FROM sprestaurant_cashcount_postdraft(f, v_c3, 'probe');
    IF v_adj IS NOT NULL THEN RAISE EXCEPTION 'FAIL 7c: a balanced count posted an adjustment'; END IF;
    IF (SELECT status FROM restaurantcashcounts WHERE countid = v_c3) <> 'Posted' THEN RAISE EXCEPTION 'FAIL 7d: balanced count not marked posted'; END IF;
    v_checks := v_checks + 4;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;

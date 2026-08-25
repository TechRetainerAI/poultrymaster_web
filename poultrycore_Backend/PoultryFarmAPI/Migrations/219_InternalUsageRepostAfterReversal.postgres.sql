-- =============================================================================
-- 219_InternalUsageRepostAfterReversal.postgres.sql
--
-- Symptom
-- -------
-- Reversed was a dead end. A record reversed by mistake -- wrong reason picked,
-- reversed on the wrong row, reversed to correct something that turned out not
-- to need correcting -- could never be put back. The only way forward was to
-- key the whole basket in again as a new draft, which left two records where
-- one event happened and made the day's internal-use list read as if the stock
-- went out twice.
--
-- Decision
-- --------
-- Allow Draft -> Posted -> Reversed -> Posted. Nothing about the posting logic
-- needed to change to make this safe -- migration 179's delta rule already
-- handles it. Post computes the NET already on the ledger for this
-- (txntype, relatedid, product) and writes only the difference needed to reach
-- -stockquantity. After a reversal that net is 0, so a re-post writes the full
-- deduction again, exactly as the first post did. The reversal row stays where
-- it is; the ledger ends up telling the whole story: out, back, out again.
--
-- Migration 212 anticipated this in as many words -- it cancels the linked
-- expense rather than deleting it "so a later re-post would still be free to
-- insert", and the filtered unique index on active expenses agrees. Poultry
-- deletes its expense row outright (the shared `expense` table has no isdeleted
-- column), which leaves the same door open. So the expense side already works.
--
-- The one thing that was actually wrong
-- -------------------------------------
-- The header keeps reversedby / reversedat / reversalreason. Left alone, a
-- re-posted record would show as Posted while still carrying "Reversed: 24 Aug
-- - Kwame - wrong row" in its history panel, which is a straight contradiction.
-- The header describes the CURRENT state, so a re-post clears those three.
-- Nothing is lost: the reversal is permanently recorded in the append-only
-- stock ledger ("Reversal of internal use ..."), and on water and generic the
-- cancelled expense row keeps its "[reversed: reason]" note.
--
-- Fix
-- ---
-- Two anchored replacements on each of the three live _post bodies, the same
-- technique migrations 206, 211, 212 and 218 use, aborting loudly if an anchor
-- has drifted rather than silently skipping:
--
--   1. IF v_status <> 'Draft'          -> IF v_status NOT IN ('Draft','Reversed')
--   2. the status UPDATE now also clears the three reversal columns
--
-- Deliberately unchanged: reverse still insists on 'Posted', so the pair stays
-- symmetrical and a Draft still cannot be reversed. Edit and delete still
-- insist on 'Draft' -- a reversed record has real ledger history behind it, so
-- re-posting it must post what it actually says, not a quietly edited version.
-- Someone who wants different figures should reverse it and write a new draft.
--
-- Re-posting still runs every check the first post ran: the record must still
-- have items, and the pre-flight refuses the whole basket if a product no
-- longer has the stock. Reversing to free up stock and then re-posting once it
-- is short therefore fails loudly instead of driving a product negative.
--
-- Idempotent: re-running finds the new text already in place and reports it.
-- No data change.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $patch$
DECLARE
    r        record;
    v_def    text;
    v_new    text;
    v_done   int := 0;

    -- The || is load-bearing. Two string literals on adjacent lines concatenate
    -- in plain SQL, but plpgsql rebuilds a DECLARE default from its own token
    -- stream and loses the newline that rule depends on, so implicit adjacency
    -- is a syntax error here. Spell the concatenation out.
    --
    -- Anchor 1: the guard that made Reversed terminal. Identical in all three.
    c_guard_old CONSTANT text :=
        E'    IF v_status <> ''Draft'' THEN\n' ||
        E'        RAISE EXCEPTION ''Cannot post a % record.'', v_status;';
    c_guard_new CONSTANT text :=
        E'    IF v_status NOT IN (''Draft'', ''Reversed'') THEN\n' ||
        E'        RAISE EXCEPTION ''Cannot post a % record.'', v_status;';

    -- Anchor 2: the status UPDATE. Also identical in all three -- only the
    -- table and key names differ, and those sit outside this fragment.
    c_upd_old CONSTANT text :=
        E'    SET    status = ''Posted'', totalcostvalue = v_total,\n' ||
        E'           postedby = p_postedby, postedat = (now() at time zone ''utc''),\n' ||
        E'           updatedat = (now() at time zone ''utc'')';
    c_upd_new CONSTANT text :=
        E'    SET    status = ''Posted'', totalcostvalue = v_total,\n' ||
        E'           postedby = p_postedby, postedat = (now() at time zone ''utc''),\n' ||
        E'           -- A re-post is not a reversed record (migration 219). The\n' ||
        E'           -- reversal survives in the ledger; the header is current state.\n' ||
        E'           reversedby = NULL, reversedat = NULL, reversalreason = NULL,\n' ||
        E'           updatedat = (now() at time zone ''utc'')';
BEGIN
    FOR r IN
        SELECT p.oid, p.proname
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spwaterinternalusage_post',
                             'sppoultryinternalusage_post',
                             'spgenericinternalusage_post')
        ORDER  BY p.proname
    LOOP
        v_def := pg_get_functiondef(r.oid);

        IF position(c_guard_new in v_def) > 0
           AND position(c_upd_new in v_def) > 0 THEN
            RAISE NOTICE '219: % already allows re-posting.', r.proname;
            v_done := v_done + 1;
            CONTINUE;
        END IF;

        IF position(c_guard_old in v_def) = 0
           AND position(c_guard_new in v_def) = 0 THEN
            RAISE EXCEPTION
                '219: the Draft-only guard is not where it should be in % -- the body has drifted, patch it by hand.',
                r.proname;
        END IF;

        IF position(c_upd_old in v_def) = 0
           AND position(c_upd_new in v_def) = 0 THEN
            RAISE EXCEPTION
                '219: the status UPDATE is not where it should be in % -- the body has drifted, patch it by hand.',
                r.proname;
        END IF;

        v_new := replace(v_def, c_guard_old, c_guard_new);
        v_new := replace(v_new, c_upd_old,   c_upd_new);

        EXECUTE v_new;
        v_done := v_done + 1;
        RAISE NOTICE '219: % can now post a reversed record again.', r.proname;
    END LOOP;

    IF v_done < 3 THEN
        RAISE EXCEPTION '219: expected 3 post functions, handled %.', v_done;
    END IF;
END;
$patch$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'post accepts Reversed (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_post','sppoultryinternalusage_post','spgenericinternalusage_post')
  AND  pg_get_functiondef(p.oid) LIKE '%NOT IN (''Draft'', ''Reversed'')%'
UNION ALL
SELECT 'post clears reversal columns (3 expected)',
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_post','sppoultryinternalusage_post','spgenericinternalusage_post')
  AND  pg_get_functiondef(p.oid) LIKE '%reversedby = NULL%'
UNION ALL
-- Reverse must still refuse anything that is not Posted, or the pair stops
-- being symmetrical and a draft could be "reversed" into nothing.
SELECT 'reverse still requires Posted (3 expected)',
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_reverse','sppoultryinternalusage_reverse','spgenericinternalusage_reverse')
  AND  pg_get_functiondef(p.oid) LIKE '%Only a posted record can be reversed%';

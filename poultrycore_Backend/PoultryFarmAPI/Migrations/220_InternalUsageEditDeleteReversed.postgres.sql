-- =============================================================================
-- 220_InternalUsageEditDeleteReversed.postgres.sql
--
-- Symptom
-- -------
-- Edit and delete were Draft-only. Migration 219 made a reversed record
-- postable again, which left it in an odd half-state: you could put it back
-- exactly as it was, but you could not correct the figure that made you reverse
-- it in the first place, and you could not get rid of it if it should never
-- have existed. The common case -- posted the wrong quantity, reversed it,
-- wanted to fix the number -- still meant keying the whole basket in again.
--
-- Decision
-- --------
-- Edit and delete now accept Draft and Reversed. Posted is unchanged: it still
-- has to be reversed first.
--
-- Reversed is safe to treat like a draft because it IS one, arithmetically. Its
-- ledger rows sum to zero for every product on it -- that is what reversing
-- did -- and its linked expense is already cancelled. So replacing its items
-- moves no stock, and neither does removing it. The record is inert; only the
-- paperwork is left.
--
-- Editing a reversed record leaves it Reversed. It does not silently re-post --
-- the user fixes the figures and then presses Post again (migration 219), which
-- is the moment stock actually moves. Two deliberate steps, because the second
-- one is the one with consequences.
--
-- What delete does with the ledger
-- --------------------------------
-- Nothing. The header and its items go; the stock rows stay exactly where they
-- are. That is the append-only rule migration 212 set out, and it costs nothing
-- here: the rows already net to zero, so they move no stock, and each one spells
-- out its own reference number in `note` ("Internal use INT-0007" and "Reversal
-- of internal use INT-0007"), so the pair still reads correctly with no header
-- to join to. Ids come from a sequence and are never reused, so a future record
-- cannot inherit the dangling relatedid.
--
-- If you would rather the rows disappeared with the record, that is a one-line
-- DELETE in each branch below -- but it is deleting history to tidy a report,
-- and it cannot be undone, so it is not the default.
--
-- The net-zero assertion
-- ----------------------
-- Each delete re-derives the sum from the ledger instead of trusting
-- status = 'Reversed'. If a record says Reversed but its rows do not cancel --
-- a half-finished reversal, a hand-edited row -- deleting the header would
-- strand a real stock movement nobody can trace back. So it refuses, loudly,
-- and says what the outstanding figure is. This should never fire. It is here
-- because the one time it does, the alternative is silent stock drift.
--
-- Water sums COALESCE(basequantity, quantity) -- base units are the truth since
-- migration 084, and the COALESCE covers rows written before it backfilled.
-- Poultry and generic sum their single quantity column.
--
-- Also unchanged: the cancelled expense rows on water and generic keep their
-- "[reversed: reason]" note and their isdeleted flag, so they stay out of every
-- report exactly as they were. Poultry deleted its expense row when it reversed.
--
-- Full CREATE OR REPLACE rather than the anchored text patching 218 and 219
-- use: these six functions are each defined exactly once (212, 216, 217) and
-- nothing since has touched them, so replacing them outright is both safe and
-- far easier to read than a body rewrite.
--
-- Idempotent: CREATE OR REPLACE only, no data change.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- WATER
-- =============================================================================
CREATE OR REPLACE FUNCTION public.spwaterinternalusage_update(
    p_waterinternalusageid integer,
    p_farmid             text,
    p_usagedate          timestamp,
    p_category           text,
    p_reason             text DEFAULT NULL,
    p_recipientname      text DEFAULT NULL,
    p_responsiblestaffid integer DEFAULT NULL,
    p_staffcount         integer DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_itemsjson          text DEFAULT NULL,
    p_updatedby          text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM waterinternalusage h
    WHERE  h.waterinternalusageid = p_waterinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_waterinternalusageid;
    END IF;
    -- Editing a POSTED record would move stock behind the ledger's back. A
    -- reversed one has already given its stock back, so it edits like a draft
    -- and stays Reversed until someone posts it again (migration 220).
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'Only a draft or a reversed record can be edited. This one is %. Reverse it first.', v_status;
    END IF;

    UPDATE waterinternalusage
    SET    usagedate          = COALESCE(p_usagedate, usagedate),
           category           = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason             = p_reason,
           recipientname      = p_recipientname,
           responsiblestaffid = p_responsiblestaffid,
           staffcount         = p_staffcount,
           notes              = p_notes,
           updatedat          = (now() at time zone 'utc')
    WHERE  waterinternalusageid = p_waterinternalusageid AND farmid = p_farmid;

    PERFORM public.spwaterinternalusage_replaceitems(p_waterinternalusageid, p_farmid, p_itemsjson);
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterinternalusage_delete(
    p_waterinternalusageid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_net    numeric(14,3);
BEGIN
    SELECT h.status INTO v_status FROM waterinternalusage h
    WHERE  h.waterinternalusageid = p_waterinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN RETURN; END IF;    -- already gone: deleting is idempotent
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it first, so the stock history survives.', v_status;
    END IF;

    -- Prove the reversal actually cancelled out before dropping the header that
    -- explains these rows. Derived from the ledger, not from the status column.
    IF v_status = 'Reversed' THEN
        SELECT COALESCE(SUM(COALESCE(st.basequantity, st.quantity)), 0) INTO v_net
        FROM   waterstocktransactions st
        WHERE  st.farmid = p_farmid
          AND  st.txntype = 'InternalUse'
          AND  st.relatedid = p_waterinternalusageid;

        IF v_net <> 0 THEN
            RAISE EXCEPTION
                'This record is marked Reversed but % base units are still out of stock. Reverse it properly before deleting it.',
                -v_net;
        END IF;
    END IF;

    -- The stock rows stay. They net to zero and each names its own reference in
    -- `note`, so the pair still reads without a header to join to.
    DELETE FROM waterinternalusage
    WHERE waterinternalusageid = p_waterinternalusageid AND farmid = p_farmid;   -- items cascade
END;
$function$;

-- =============================================================================
-- POULTRY
-- =============================================================================
CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_update(
    p_poultryinternalusageid integer,
    p_farmid             text,
    p_usagedate          timestamp,
    p_category           text,
    p_reason             text DEFAULT NULL,
    p_recipientname      text DEFAULT NULL,
    p_responsiblestaffid integer DEFAULT NULL,
    p_staffcount         integer DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_itemsjson          text DEFAULT NULL,
    p_updatedby          text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM poultryinternalusage h
    WHERE  h.poultryinternalusageid = p_poultryinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_poultryinternalusageid;
    END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'Only a draft or a reversed record can be edited. This one is %. Reverse it first.', v_status;
    END IF;

    UPDATE poultryinternalusage
    SET    usagedate          = COALESCE(p_usagedate, usagedate),
           category           = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason             = p_reason,
           recipientname      = p_recipientname,
           responsiblestaffid = p_responsiblestaffid,
           staffcount         = p_staffcount,
           notes              = p_notes,
           updatedat          = (now() at time zone 'utc')
    WHERE  poultryinternalusageid = p_poultryinternalusageid AND farmid = p_farmid;

    PERFORM public.sppoultryinternalusage_replaceitems(p_poultryinternalusageid, p_farmid, p_itemsjson);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_delete(
    p_poultryinternalusageid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_net    numeric(14,3);
BEGIN
    SELECT h.status INTO v_status FROM poultryinternalusage h
    WHERE  h.poultryinternalusageid = p_poultryinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it first, so the stock history survives.', v_status;
    END IF;

    IF v_status = 'Reversed' THEN
        SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid
          AND  t.txntype = 'InternalUse'
          AND  t.relatedid = p_poultryinternalusageid;

        IF v_net <> 0 THEN
            RAISE EXCEPTION
                'This record is marked Reversed but % units are still out of stock. Reverse it properly before deleting it.',
                -v_net;
        END IF;
    END IF;

    DELETE FROM poultryinternalusage
    WHERE poultryinternalusageid = p_poultryinternalusageid AND farmid = p_farmid;
END;
$function$;

-- =============================================================================
-- GENERIC
-- =============================================================================
CREATE OR REPLACE FUNCTION public.spgenericinternalusage_update(
    p_genericinternalusageid integer,
    p_farmid             text,
    p_usagedate          timestamp,
    p_category           text,
    p_reason             text DEFAULT NULL,
    p_recipientname      text DEFAULT NULL,
    p_responsiblestaffid integer DEFAULT NULL,
    p_staffcount         integer DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_itemsjson          text DEFAULT NULL,
    p_updatedby          text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM genericinternalusage h
    WHERE  h.genericinternalusageid = p_genericinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_genericinternalusageid;
    END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'Only a draft or a reversed record can be edited. This one is %. Reverse it first.', v_status;
    END IF;

    UPDATE genericinternalusage
    SET    usagedate          = COALESCE(p_usagedate, usagedate),
           category           = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason             = p_reason,
           recipientname      = p_recipientname,
           responsiblestaffid = p_responsiblestaffid,
           staffcount         = p_staffcount,
           notes              = p_notes,
           updatedat          = (now() at time zone 'utc')
    WHERE  genericinternalusageid = p_genericinternalusageid AND farmid = p_farmid;

    PERFORM public.spgenericinternalusage_replaceitems(p_genericinternalusageid, p_farmid, p_itemsjson);
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericinternalusage_delete(
    p_genericinternalusageid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_net    numeric(14,3);
BEGIN
    SELECT h.status INTO v_status FROM genericinternalusage h
    WHERE  h.genericinternalusageid = p_genericinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it first, so the stock history survives.', v_status;
    END IF;

    IF v_status = 'Reversed' THEN
        SELECT COALESCE(SUM(m.quantity), 0) INTO v_net
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid
          AND  m.referencetype = 'GenericInternalUsage'
          AND  m.referenceid = p_genericinternalusageid;

        IF v_net <> 0 THEN
            RAISE EXCEPTION
                'This record is marked Reversed but % units are still out of stock. Reverse it properly before deleting it.',
                -v_net;
        END IF;
    END IF;

    DELETE FROM genericinternalusage
    WHERE genericinternalusageid = p_genericinternalusageid AND farmid = p_farmid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'edit accepts Reversed (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_update','sppoultryinternalusage_update','spgenericinternalusage_update')
  AND  pg_get_functiondef(p.oid) LIKE '%NOT IN (''Draft'', ''Reversed'')%'
UNION ALL
SELECT 'delete accepts Reversed (3 expected)',
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_delete','sppoultryinternalusage_delete','spgenericinternalusage_delete')
  AND  pg_get_functiondef(p.oid) LIKE '%NOT IN (''Draft'', ''Reversed'')%'
UNION ALL
SELECT 'delete asserts the reversal netted to zero (3 expected)',
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_delete','sppoultryinternalusage_delete','spgenericinternalusage_delete')
  AND  pg_get_functiondef(p.oid) LIKE '%still out of stock%'
UNION ALL
-- Posted must stay locked on both paths, or the append-only rule is gone.
SELECT 'Posted still locked, edit + delete (6 expected)',
       CASE WHEN count(*) = 6 THEN 'OK' ELSE 'ONLY ' || count(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_update','sppoultryinternalusage_update','spgenericinternalusage_update',
                     'spwaterinternalusage_delete','sppoultryinternalusage_delete','spgenericinternalusage_delete')
  AND  pg_get_functiondef(p.oid) LIKE '%Reverse it first%';

-- Any reversed record whose ledger does NOT cancel out. Expect zero rows; each
-- one listed here is a record delete will refuse until it is reversed properly.
SELECT 'water' AS module, h.waterinternalusageid AS id, h.referenceno,
       COALESCE(SUM(COALESCE(st.basequantity, st.quantity)), 0) AS outstanding
FROM   waterinternalusage h
LEFT   JOIN waterstocktransactions st
       ON st.farmid = h.farmid AND st.txntype = 'InternalUse'
      AND st.relatedid = h.waterinternalusageid
WHERE  h.status = 'Reversed'
GROUP  BY h.waterinternalusageid, h.referenceno
HAVING COALESCE(SUM(COALESCE(st.basequantity, st.quantity)), 0) <> 0;

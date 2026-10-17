-- =============================================================================
-- 379_PoultryByproductEntryTime.postgres.sql                    (requires 375)
--
-- Purpose
-- -------
-- Broken Eggs / Dead Birds rows written by a production record or egg sorting
-- (sppoultrybyproduct_post, 372) were stamped createddate = the RECORD'S DATE
-- at midnight, with no effectivedate. Stock movements sorts by createddate, so
-- they sank below every row entered that day -- a back-dated record's rows
-- landed among that older day's rows, often on a later page -- and looked
-- missing next to the record's own "Production" and "Mortality" rows.
--
-- Now, like manual movements (373):
--   createddate   = when it was entered (sorts with the record's other rows)
--   effectivedate = the record's date (what reports date it by)
-- fnpoultry_byproductledger already dates by COALESCE(effectivedate,
-- createddate::date), so every report keeps the same day.
--
-- Backfill: existing byproduct rows get effectivedate = their old date and,
-- where they belong to a production record, that record's entry time.
-- Quantities are not touched.
-- =============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultrybyproduct_post(p_farmid text, p_role text, p_txntype text, p_relatedid integer, p_target numeric, p_date date, p_note text, p_by text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_prod  integer := fnpoultry_byproduct(p_farmid, p_role);
    v_net   numeric;
    v_delta numeric;
BEGIN
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net FROM poultrystocktransactions t
    WHERE  t.farmid = p_farmid AND t.poultryproductid = v_prod AND t.txntype = p_txntype AND t.relatedid = p_relatedid;
    v_delta := COALESCE(p_target, 0) - v_net;
    IF v_delta = 0 THEN RETURN 0; END IF;
    -- 379: entered now, effective on the record's date.
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby, createddate, effectivedate)
    VALUES (p_farmid, v_prod, p_txntype, v_delta, p_relatedid,
            left(CASE WHEN COALESCE(p_target, 0) = 0 THEN 'Reversal: ' || COALESCE(p_note, p_txntype) ELSE p_note END, 500),
            p_by, (now() AT TIME ZONE 'utc'),
            COALESCE(p_date, (now() AT TIME ZONE 'utc')::date));
    RETURN v_delta;
END
$function$;

-- Backfill. Production-record rows take the record's entry time; egg-sorting
-- rows keep their timestamp.
UPDATE poultrystocktransactions t
SET    effectivedate = t.createddate::date,
       createddate   = COALESCE(
           CASE WHEN t.txntype IN ('Broken Egg Prod', 'Broken Egg Disposal', 'Mortality In', 'Mortality Disposal')
                THEN (SELECT pr.createdat FROM productionrecords pr
                      WHERE pr.id = t.relatedid AND pr.farmid = t.farmid) END,
           t.createddate)
FROM   poultryproducts p
WHERE  p.poultryproductid = t.poultryproductid
  AND  p.systemrole IS NOT NULL
  AND  t.effectivedate IS NULL
  AND  t.manualmovementid IS NULL;

DO $$
DECLARE v_n integer;
BEGIN
    SELECT count(*) INTO v_n FROM poultrystocktransactions t JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
    WHERE  p.systemrole IS NOT NULL AND t.effectivedate IS NULL;
    IF v_n > 0 THEN RAISE EXCEPTION '379: % byproduct row(s) still have no effective date', v_n; END IF;
    RAISE NOTICE '379: byproduct rows now carry their entry time and effective date';
END
$$;

COMMIT;

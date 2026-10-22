-- =============================================================================
-- 384_PoultryOldDebtSaleType.postgres.sql                        (requires 382, 383)
--
-- Purpose
-- -------
-- 2026-10-22, Record customer payment (Payments page). 383 made money left over
-- after the open sales an old debt (on Profit & Loss) by DEFAULT. Reversed by
-- the business: the leftover is now customer credit by default, and the user
-- ticks "This pays for a sale made before the system -- add to Profit & Loss"
-- and says WHAT was sold (Fresh Eggs, Chicken, Broken Eggs, Dead Birds,
-- Manure, or Other typed in). The default flip is in the dialog only; this
-- migration records the sale type and shows it on P&L.
--
--   poultrycustomerdebts.saletype           what the old debt was for (NULL on
--                                           debts recorded any other way)
--   sppoultrycustomerpayment_recordolddebt  + p_saletype (DEFAULT NULL, last),
--                                           stored on the debt and named in its
--                                           description
--   sppoultryreport_plrevenuedetail         the Customer Debt Collections arm
--                                           reads "Old debt collected: Fresh
--                                           Eggs - Debt CD-00012 - payment ..."
--
-- The P&L line itself (sppoultryreport_pllines 'DebtCollections') and the
-- supplier side are unchanged.
--
-- API ORDER: the API only passes p_saletype when a type was chosen, so an API
-- deployed before this migration still records old debts without one.
-- =============================================================================

BEGIN;

ALTER TABLE poultrycustomerdebts ADD COLUMN IF NOT EXISTS saletype text;

-- ------------------------------------------------ 1. record the sale type ----
-- A new trailing parameter makes a new overload, and two overloads make every
-- named-argument call ambiguous: drop every one BY NAME, create exactly one.
DO $d$ DECLARE r record; BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'sppoultrycustomerpayment_recordolddebt'
    LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig; END LOOP;
END $d$;

CREATE FUNCTION public.sppoultrycustomerpayment_recordolddebt(
    p_farmid text, p_customerid integer, p_amount numeric, p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL, p_paymentdate timestamp DEFAULT NULL,
    p_cashaccountid integer DEFAULT NULL, p_reference text DEFAULT NULL, p_note text DEFAULT NULL,
    p_sourcetype text DEFAULT 'PaymentsPage', p_createdby text DEFAULT NULL,
    p_saletype text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE
    v_alloc  jsonb := COALESCE(p_allocations, '[]'::jsonb);
    v_used   numeric(14,2);
    v_rest   numeric(14,2);
    v_res    jsonb;
    v_debt   integer;
    v_date   timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_type   text := NULLIF(btrim(p_saletype), '');   -- 384
BEGIN
    SELECT COALESCE(SUM(a.amount), 0) INTO v_used
    FROM   jsonb_to_recordset(v_alloc) AS a(saleid integer, debtid integer, amount numeric)
    WHERE  (a.saleid IS NOT NULL OR a.debtid IS NOT NULL) AND COALESCE(a.amount, 0) <> 0;
    v_rest := round(COALESCE(p_amount, 0), 2) - v_used;

    IF v_rest > 0 THEN
        IF p_cashaccountid IS NULL THEN
            RAISE EXCEPTION 'Choose the cash account the money was received into.' USING ERRCODE = 'P0001';
        END IF;
        v_res := sppoultrycustomerdebt_create(p_farmid, p_customerid, v_rest, v_date::date, 'HistoricalDebt',
                     COALESCE(v_type || ' sold before the system', 'Owed before the system')   -- 384
                         || ' -- paid on ' || to_char(v_date, 'DD Mon YYYY')
                         || COALESCE(' (' || NULLIF(btrim(p_note), '') || ')', ''),
                     p_reference, NULL, p_createdby);
        v_debt := (v_res->>'debtId')::integer;
        UPDATE poultrycustomerdebts SET paidonentry = TRUE, saletype = v_type   -- 384: saletype
        WHERE  debtid = v_debt AND farmid = p_farmid;
        v_alloc := v_alloc || jsonb_build_array(jsonb_build_object('debtid', v_debt, 'amount', v_rest));
    END IF;

    RETURN sppoultrycustomerpayment_record(p_farmid, p_customerid, p_amount, v_alloc, p_paymentmethod, v_date,
                                           p_cashaccountid, p_reference, p_note, p_sourcetype, p_createdby);
END;
$function$;

-- ------------------------------------------- 2. P&L revenue detail -----------
-- Patched in place from the LIVE body (pg_get_functiondef), not rewritten from
-- 382: only the Debt Collections product text changes. Whitespace-tolerant
-- anchor; RAISES when it is missing so a drifted body aborts the migration.
DO $p$
DECLARE
    v_def  text;
    v_new  text;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'sppoultryreport_plrevenuedetail';

    IF v_def IS NULL THEN
        RAISE EXCEPTION '384: sppoultryreport_plrevenuedetail not found';
    END IF;
    IF position('Old debt collected' IN v_def) > 0 THEN
        RAISE NOTICE '384: sppoultryreport_plrevenuedetail already patched, skipped';
        RETURN;
    END IF;

    v_new := regexp_replace(v_def,
        $re$\(\s*'Debt '\s*\|\|\s*COALESCE\(\s*d\.debtnumber\s*,$re$,
        $rp$(CASE WHEN d.saletype IS NOT NULL THEN 'Old debt collected: ' || d.saletype || ' - ' ELSE '' END   -- 384
                    || 'Debt ' || COALESCE(d.debtnumber,$rp$);

    IF v_new = v_def THEN
        RAISE EXCEPTION '384: Debt Collections anchor not found in sppoultryreport_plrevenuedetail -- live body has drifted';
    END IF;

    EXECUTE v_new;
END $p$;

COMMIT;

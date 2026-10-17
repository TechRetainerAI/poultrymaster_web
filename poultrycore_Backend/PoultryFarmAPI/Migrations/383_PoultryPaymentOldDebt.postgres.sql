-- =============================================================================
-- 383_PoultryPaymentOldDebt.postgres.sql                    (requires 369, 370, 382)
--
-- Purpose
-- -------
-- User, 2026-10-16: "Record customer payment" (Payments page) is revenue and
-- "Record supplier payment" (Supplier Payments) is an operating expense --
-- unless the user says otherwise. Money there that pays no recorded sale,
-- purchase or debt is a payment of something owed from before the system, NOT
-- an advance.
--
-- So the part left over is recorded as a debt and paid in the same step:
--   sppoultrycustomerpayment_recordolddebt  customer debt (CD-) + payment on it
--   sppoultrysupplierpayment_recordolddebt  supplier debt (SD-) + payment on it
-- Both take the same arguments as the plain record functions. The debt is
-- 'HistoricalDebt', dated the payment date, marked paidonentry. From there 382
-- does the rest: Customer Debt Collections (revenue) / Supplier Debt Payments
-- (operating expense), excludable per payment. No credit is created.
-- "Keep as credit (advance)" in the dialog calls the plain record function.
--
-- Reversing such a payment would leave its debt owed again -- money nobody
-- owes. sppoultrypayment_releaseolddebts / sppoultrysupplierpayment_releaseolddebts
-- reverse the paidonentry debts a reversed payment had paid (the API calls them
-- in the same transaction as the reversal).
-- =============================================================================

ALTER TABLE poultrycustomerdebts ADD COLUMN IF NOT EXISTS paidonentry boolean NOT NULL DEFAULT false;
ALTER TABLE poultrysupplierdebts ADD COLUMN IF NOT EXISTS paidonentry boolean NOT NULL DEFAULT false;

-- ------------------------------------------------------------- customer ----
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpayment_recordolddebt(
    p_farmid text, p_customerid integer, p_amount numeric, p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL, p_paymentdate timestamp DEFAULT NULL,
    p_cashaccountid integer DEFAULT NULL, p_reference text DEFAULT NULL, p_note text DEFAULT NULL,
    p_sourcetype text DEFAULT 'PaymentsPage', p_createdby text DEFAULT NULL)
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
                     'Owed before the system -- paid on ' || to_char(v_date, 'DD Mon YYYY')
                         || COALESCE(' (' || NULLIF(btrim(p_note), '') || ')', ''),
                     p_reference, NULL, p_createdby);
        v_debt := (v_res->>'debtId')::integer;
        UPDATE poultrycustomerdebts SET paidonentry = TRUE WHERE debtid = v_debt AND farmid = p_farmid;
        v_alloc := v_alloc || jsonb_build_array(jsonb_build_object('debtid', v_debt, 'amount', v_rest));
    END IF;

    RETURN sppoultrycustomerpayment_record(p_farmid, p_customerid, p_amount, v_alloc, p_paymentmethod, v_date,
                                           p_cashaccountid, p_reference, p_note, p_sourcetype, p_createdby);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrypayment_releaseolddebts(p_farmid text, p_paymentgroupid uuid, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_d  record;
    v_n  integer := 0;
BEGIN
    FOR v_d IN
        SELECT DISTINCT d.debtid, d.amount
        FROM   poultrypayments pp
        JOIN   poultrycustomerdebts d ON d.debtid = pp.debtid AND d.farmid = pp.farmid
        WHERE  pp.farmid = p_farmid AND pp.paymentgroupid = p_paymentgroupid
          AND  d.paidonentry AND d.status = 'Posted'
    LOOP
        -- Only once nothing is paid on it any more (another payment may have paid part).
        IF fnpoultrycustomerdebt_balance(p_farmid, v_d.debtid) >= v_d.amount THEN
            PERFORM sppoultrycustomerdebt_reverse(p_farmid, v_d.debtid, 'Its payment was reversed', p_by);
            v_n := v_n + 1;
        END IF;
    END LOOP;
    RETURN v_n;
END;
$function$;

-- ------------------------------------------------------------- supplier ----
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_recordolddebt(
    p_farmid text, p_supplierid integer, p_amount numeric, p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL, p_paymentdate timestamp DEFAULT NULL,
    p_cashaccountid integer DEFAULT NULL, p_reference text DEFAULT NULL, p_notes text DEFAULT NULL,
    p_sourcetype text DEFAULT 'SupplierPayments', p_createdby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_alloc  jsonb := COALESCE(p_allocations, '[]'::jsonb);
    v_used   numeric(14,2);
    v_rest   numeric(14,2);
    v_res    jsonb;
    v_debt   integer;
    v_date   timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
BEGIN
    SELECT COALESCE(SUM(a.amount), 0) INTO v_used
    FROM   jsonb_to_recordset(v_alloc) AS a(documentid integer, amount numeric)
    WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0;
    v_rest := round(COALESCE(p_amount, 0), 2) - v_used;

    IF v_rest > 0 THEN
        IF p_supplierid IS NULL THEN
            RAISE EXCEPTION 'Choose the supplier this was owed to.' USING ERRCODE = 'P0001';
        END IF;
        v_res := sppoultrysupplierdebt_create(p_farmid, p_supplierid, v_rest, v_date::date, 'HistoricalDebt',
                     'Owed before the system -- paid on ' || to_char(v_date, 'DD Mon YYYY')
                         || COALESCE(' (' || NULLIF(btrim(p_notes), '') || ')', ''),
                     p_reference, NULL, p_createdby);
        v_debt := (v_res->>'debtId')::integer;
        UPDATE poultrysupplierdebts SET paidonentry = TRUE WHERE debtid = v_debt AND farmid = p_farmid;
        v_alloc := v_alloc || jsonb_build_array(jsonb_build_object('documenttype', 'SupplierDebt', 'documentid', v_debt, 'amount', v_rest));
    END IF;

    RETURN sppoultrysupplierpayment_record(p_farmid, p_supplierid, p_amount, v_alloc, p_paymentmethod, v_date,
                                           p_cashaccountid, p_reference, p_notes, p_sourcetype, p_createdby);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_releaseolddebts(p_farmid text, p_paymentid integer, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_d  record;
    v_n  integer := 0;
BEGIN
    FOR v_d IN
        SELECT DISTINCT d.debtid
        FROM   supplierpaymentallocation sa
        JOIN   poultrysupplierdebts d ON d.debtid = sa.documentid AND d.farmid = sa.farmid
        WHERE  sa.farmid = p_farmid AND sa.paymentid = p_paymentid
          AND  sa.module = 'poultry' AND sa.documenttype = 'SupplierDebt'
          AND  d.paidonentry AND d.status = 'Posted'
    LOOP
        IF (SELECT d.amountpaid FROM poultrysupplierdebts d WHERE d.debtid = v_d.debtid) = 0
           AND NOT EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                           WHERE sa.farmid = p_farmid AND sa.documenttype = 'SupplierDebt'
                             AND sa.documentid = v_d.debtid AND COALESCE(sa.status, 'Posted') = 'Posted') THEN
            PERFORM sppoultrysupplierdebt_reverse(p_farmid, v_d.debtid, 'Its payment was reversed', p_by);
            v_n := v_n + 1;
        END IF;
    END LOOP;
    RETURN v_n;
END;
$function$;

-- 356. Record Purchase: the money paid up front is a supplier payment.
--
-- Supplier Payments lists poultrysupplierpayments. Receive Invoice (345) and
-- Pay balance both pay through sppoultrysupplierpayment_record, so their money
-- is listed there. Record Purchase did not: it wrote "amount paid" straight
-- onto the purchase with its own expense row and cash line, so the payment
-- made on the day of purchase never appeared in Supplier Payments.
--
-- Now Record Purchase works like Receive Invoice:
--   1. the lot is saved with nothing paid (sppoultryrawmaterialpurchase_insert,
--      p_amountpaid => 0; 355 resolves the supplier);
--   2. its cash account is set (no cash moves yet, nothing is paid);
--   3. the amount paid is recorded as ONE supplier payment allocated to the
--      lot, source 'RecordPurchase'. That one call posts the cash-out, the
--      expense line (or none, for a deferred-cost lot) and the ledger row --
--      the same way every other supplier payment does, so nothing is counted
--      twice.
--
-- And so the ledger and the purchase can never disagree afterwards:
--   * EDIT: once a purchase has a posted supplier payment, its amount paid is
--     changed only through Supplier Payments (pay more, or reverse one), not
--     by typing a new figure into the purchase.
--   * DELETE: a payment that paid only this purchase is reversed with it. A
--     payment shared with other documents must be reversed by hand first.
--
-- Older purchases keep their earlier upfront payments as they were: moving
-- those into the ledger would post their cash a second time.
--
-- Run AFTER 355. Idempotent: the patches check for their own marker first.

-- 1. Record Purchase, start to finish ----------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_record(
    p_farmid text, p_poultryrawmaterialitemid integer,
    p_suppliername text DEFAULT NULL, p_supplierid integer DEFAULT NULL,
    p_purchasedate timestamp without time zone DEFAULT NULL,
    p_quantity numeric DEFAULT NULL, p_unitcost numeric DEFAULT NULL, p_totalcost numeric DEFAULT NULL,
    p_productionunit text DEFAULT NULL, p_productionunitsperpurchaseunit numeric DEFAULT NULL,
    p_paymentmethod text DEFAULT NULL, p_amountpaid numeric DEFAULT 0,
    p_receipturl text DEFAULT NULL, p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL,
    p_poultrycashaccountid integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id     integer;
    v_paid   numeric(14,2) := COALESCE(p_amountpaid, 0);
    v_total  numeric(14,2);
    v_sup    integer;
    v_date   timestamp;
    v_method text := NULLIF(btrim(COALESCE(p_paymentmethod, '')), '');
BEGIN
    IF v_paid < 0 THEN
        RAISE EXCEPTION 'Amount paid cannot be negative.';
    END IF;

    v_id := public.sppoultryrawmaterialpurchase_insert(
        p_farmid => p_farmid, p_poultryrawmaterialitemid => p_poultryrawmaterialitemid,
        p_suppliername => p_suppliername, p_supplierid => p_supplierid,
        p_purchasedate => p_purchasedate, p_quantity => p_quantity, p_unitcost => p_unitcost,
        p_totalcost => p_totalcost, p_productionunit => p_productionunit,
        p_productionunitsperpurchaseunit => p_productionunitsperpurchaseunit,
        p_paymentmethod => p_paymentmethod,
        p_amountpaid => 0,                 -- money moves ONLY through the payment below
        p_receipturl => p_receipturl, p_notes => p_notes, p_createdby => p_createdby);

    -- Remember the account on the lot (later Pay balance uses it). Nothing is
    -- paid yet, so this posts no cash.
    PERFORM public.sppoultryrawmaterialpurchasecash_sync(p_farmid, v_id, p_poultrycashaccountid, TRUE, p_createdby);

    IF v_paid > 0 THEN
        SELECT pu.totalcost, pu.supplierid, pu.purchasedate INTO v_total, v_sup, v_date
        FROM   poultryrawmaterialpurchases pu
        WHERE  pu.poultryrawmaterialpurchaseid = v_id AND pu.farmid = p_farmid;
        IF v_paid > v_total THEN
            RAISE EXCEPTION 'Amount paid (%) is more than the purchase total (%).', v_paid, v_total;
        END IF;

        PERFORM public.sppoultrysupplierpayment_record(
            p_farmid        => p_farmid,
            p_supplierid    => v_sup,
            p_amount        => v_paid,
            p_allocations   => jsonb_build_array(jsonb_build_object(
                                   'documenttype', 'RawMaterialPurchase',
                                   'documentid',   v_id,
                                   'amount',       v_paid)),
            -- "Credit" names the unpaid part; what WAS paid went out as cash.
            p_paymentmethod => CASE WHEN v_method IS NULL OR lower(v_method) = 'credit' THEN 'Cash' ELSE v_method END,
            p_paymentdate   => v_date,
            p_cashaccountid => p_poultrycashaccountid,
            p_reference     => 'P' || v_id::text,
            p_notes         => 'Paid when the purchase was recorded',
            p_sourcetype    => 'RecordPurchase',
            p_createdby     => p_createdby);
    END IF;

    RETURN v_id;
END;
$function$;

-- 2 + 3. Edit and delete keep the ledger and the purchase in step -------------
DO $patch$
DECLARE
    v_name  text;
    v_def   text;
    v_guard text;
    v_n     int;
BEGIN
    FOREACH v_name IN ARRAY ARRAY['sppoultryrawmaterialpurchase_update', 'sppoultryrawmaterialpurchase_delete'] LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.proname = v_name;
        IF v_def IS NULL THEN
            RAISE EXCEPTION '356: % not found.', v_name;
        END IF;
        CONTINUE WHEN position('-- 356.' IN v_def) > 0;

        -- The top-level BEGIN, whichever line ending the function was saved with.
        SELECT count(*) INTO v_n FROM regexp_matches(v_def, E'\\nBEGIN\\r?\\n', 'g');
        IF v_n <> 1 THEN
            RAISE EXCEPTION '356: % has % top-level BEGINs; patch it by hand.', v_name, v_n;
        END IF;

        IF v_name = 'sppoultryrawmaterialpurchase_update' THEN
            v_guard :=
                E'    -- 356. Paid through Supplier Payments: change it there, not here.\n'
             || E'    IF EXISTS (SELECT 1 FROM public.supplierpaymentallocation sa\n'
             || E'               WHERE sa.farmid = p_farmid AND sa.module = ''poultry'' AND sa.status = ''Posted''\n'
             || E'                 AND sa.documenttype = ''RawMaterialPurchase'' AND sa.documentid = p_poultryrawmaterialpurchaseid)\n'
             || E'       AND (SELECT pu.amountpaid FROM public.poultryrawmaterialpurchases pu\n'
             || E'            WHERE pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid)\n'
             || E'           IS DISTINCT FROM COALESCE(p_amountpaid, 0)::numeric(14,2) THEN\n'
             || E'        RAISE EXCEPTION ''This purchase has payments in Supplier Payments. Change what was paid there (pay the balance, or reverse a payment), not by editing the amount paid.'';\n'
             || E'    END IF;\n';
        ELSE
            v_guard :=
                E'    -- 356. Reverse the supplier payments that paid only this purchase;\n'
             || E'    -- refuse when a payment also covered other documents.\n'
             || E'    DECLARE\n'
             || E'        v356 record;\n'
             || E'    BEGIN\n'
             || E'        FOR v356 IN\n'
             || E'            SELECT sa.paymentid,\n'
             || E'                   bool_and(sa.documenttype = ''RawMaterialPurchase'' AND sa.documentid = p_poultryrawmaterialpurchaseid) AS only_this\n'
             || E'            FROM   public.supplierpaymentallocation sa\n'
             || E'            WHERE  sa.farmid = p_farmid AND sa.module = ''poultry'' AND sa.status = ''Posted''\n'
             || E'              AND  sa.paymentid IN (SELECT x.paymentid FROM public.supplierpaymentallocation x\n'
             || E'                                    WHERE x.farmid = p_farmid AND x.module = ''poultry'' AND x.status = ''Posted''\n'
             || E'                                      AND x.documenttype = ''RawMaterialPurchase'' AND x.documentid = p_poultryrawmaterialpurchaseid)\n'
             || E'            GROUP  BY sa.paymentid\n'
             || E'        LOOP\n'
             || E'            IF NOT v356.only_this THEN\n'
             || E'                RAISE EXCEPTION ''Supplier payment #% also paid other items. Reverse it in Supplier Payments before deleting this purchase.'', v356.paymentid;\n'
             || E'            END IF;\n'
             || E'            PERFORM public.sppoultrysupplierpayment_reverse(p_farmid, v356.paymentid,\n'
             || E'                ''Purchase #'' || p_poultryrawmaterialpurchaseid::text || '' deleted'', NULL);\n'
             || E'        END LOOP;\n'
             || E'    END;\n';
        END IF;

        EXECUTE regexp_replace(v_def, E'(\\nBEGIN\\r?\\n)', E'\\1' || v_guard);   -- first match only
    END LOOP;
END;
$patch$;

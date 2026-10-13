-- 357. Move an older Record Purchase upfront payment into Supplier Payments.
--
-- Before 356 (and while an API still ran the old insert), the money paid when
-- a purchase was recorded went straight onto the purchase, with its own
-- expense row and its own cash line, and never reached Supplier Payments.
--
-- sppoultryrawmaterialpurchase_moveupfrontpayment replays that money through
-- the supplier-payment path, without moving it twice:
--   1. the part of amountpaid no supplier payment accounts for is taken off
--      the purchase, together with the purchase's own expense row;
--   2. the purchase's cash line is re-synced (that cash comes back);
--   3. the same amount is recorded as one supplier payment on the purchase
--      date, from the purchase's cash account (that cash goes out again, and
--      its expense row is written again for an expensed lot).
-- The cash balance, the expense total and the purchase's amount paid end
-- exactly where they started. Only Supplier Payments gains the row.
--
-- Run AFTER 356. The function is idempotent per purchase: once nothing is left
-- outside the ledger it does nothing.

CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_moveupfrontpayment(
    p_farmid text, p_poultryrawmaterialpurchaseid integer, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    pu        record;
    v_ledger  numeric(14,2);
    v_left    numeric(14,2);
    v_expid   integer;
    v_expamt  numeric(14,2);
    v_method  text;
    v_payid   integer;
    v_allowneg boolean;
BEGIN
    SELECT p.* INTO pu FROM poultryrawmaterialpurchases p
    WHERE  p.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND p.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Purchase % not found for this company.', p_poultryrawmaterialpurchaseid;
    END IF;
    IF pu.reversedat IS NOT NULL THEN
        RETURN NULL;                       -- a reversed receipt lot owes and holds nothing
    END IF;

    SELECT COALESCE(sum(sa.amountapplied), 0) INTO v_ledger
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
      AND  sa.documenttype = 'RawMaterialPurchase' AND sa.documentid = p_poultryrawmaterialpurchaseid;

    v_left := COALESCE(pu.amountpaid, 0) - v_ledger;
    IF v_left <= 0 THEN
        RETURN NULL;                       -- already all in the ledger
    END IF;

    -- The purchase's own expense row: the earliest linked row that is not a
    -- supplier payment's. None on a deferred-cost lot.
    SELECT e.expenseid, e.amount INTO v_expid, v_expamt
    FROM   expense e
    WHERE  e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = p_poultryrawmaterialpurchaseid
      AND  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.description, '') NOT LIKE 'Supplier payment #%'
    ORDER  BY e.expenseid
    LIMIT  1;

    IF v_expid IS NOT NULL THEN
        IF v_expamt < v_left THEN
            RAISE EXCEPTION 'Purchase %: its expense (%) is less than the upfront payment (%); fix it by hand.',
                  p_poultryrawmaterialpurchaseid, v_expamt, v_left;
        ELSIF v_expamt = v_left THEN
            DELETE FROM expense e WHERE e.expenseid = v_expid;
        ELSE
            UPDATE expense e SET amount = e.amount - v_left WHERE e.expenseid = v_expid;
        END IF;
    END IF;

    UPDATE poultryrawmaterialpurchases p
    SET    amountpaid = p.amountpaid - v_left, updatedat = (now() at time zone 'utc')
    WHERE  p.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND p.farmid = p_farmid;

    PERFORM public.sppoultryrawmaterialpurchasecash_sync(
        p_farmid, p_poultryrawmaterialpurchaseid, pu.poultrycashaccountid, FALSE, COALESCE(p_by, pu.createdby));

    v_method := NULLIF(btrim(COALESCE(pu.paymentmethod, '')), '');

    -- The cash already left when the purchase was recorded; this only re-files
    -- it. An account that is overdrawn today must not block that, so its
    -- no-overdraft rule is lifted for this one payment and put straight back.
    SELECT a.allownegativebalance INTO v_allowneg
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = pu.poultrycashaccountid AND a.farmid = p_farmid;
    IF v_allowneg = FALSE THEN
        UPDATE poultrycashaccounts a SET allownegativebalance = TRUE
        WHERE  a.poultrycashaccountid = pu.poultrycashaccountid;
    END IF;

    v_payid := public.sppoultrysupplierpayment_record(
        p_farmid        => p_farmid,
        p_supplierid    => pu.supplierid,
        p_amount        => v_left,
        p_allocations   => jsonb_build_array(jsonb_build_object(
                               'documenttype', 'RawMaterialPurchase',
                               'documentid',   p_poultryrawmaterialpurchaseid,
                               'amount',       v_left)),
        p_paymentmethod => CASE WHEN v_method IS NULL OR lower(v_method) = 'credit' THEN 'Cash' ELSE v_method END,
        p_paymentdate   => pu.purchasedate,
        p_cashaccountid => pu.poultrycashaccountid,
        p_reference     => 'P' || p_poultryrawmaterialpurchaseid::text,
        p_notes         => 'Paid when the purchase was recorded',
        p_sourcetype    => 'RecordPurchase',
        p_createdby     => COALESCE(p_by, pu.createdby));

    IF v_allowneg = FALSE THEN
        UPDATE poultrycashaccounts a SET allownegativebalance = FALSE
        WHERE  a.poultrycashaccountid = pu.poultrycashaccountid;
    END IF;

    RETURN v_payid;
END;
$function$;

-- Purchases recorded on 2026-10-12, while the old API was still running
-- (#772, #777, #787 at the time of writing). Older history is left alone; run
-- the function for any purchase id to move it too.
DO $run$
DECLARE r record; v_pay integer;
BEGIN
    FOR r IN
        SELECT p.farmid, p.poultryrawmaterialpurchaseid AS id
        FROM   poultryrawmaterialpurchases p
        WHERE  p.createdat >= '2026-10-12' AND p.amountpaid > 0
          AND  p.sourcefeedproductionbatchid IS NULL
          AND  NOT EXISTS (SELECT 1 FROM poultrypurchasereceiptlines l WHERE l.poultryrawmaterialpurchaseid = p.poultryrawmaterialpurchaseid)
        ORDER  BY p.poultryrawmaterialpurchaseid
    LOOP
        v_pay := public.sppoultryrawmaterialpurchase_moveupfrontpayment(r.farmid, r.id, NULL);
        IF v_pay IS NOT NULL THEN
            RAISE NOTICE 'Purchase #%: upfront payment is now supplier payment #%', r.id, v_pay;
        END IF;
    END LOOP;
END;
$run$;

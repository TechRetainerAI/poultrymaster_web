-- 427 (was 418): Supply purchases are reversed, not deleted.
--
-- Until now the only way to undo a purchase on /poultry-supply-purchases was
-- Delete, which removed the row outright -- and refused as soon as any of the
-- lot had been drawn by a production record (about half of all lots), so it
-- looked like "reverse stopped working". The farm wants a purchase to stay in
-- the list marked Reversed, like a reversed purchase receipt (345).
--
--   poultryrawmaterialpurchases.reversalreason / reversedby   new columns
--                                                             (reversedat is from 345)
--   sppoultryrawmaterialpurchase_reversalblockers(farm, id)   why it can't be reversed now
--   sppoultryrawmaterialpurchase_reverse(farm, id, reason, by)
--
-- Reversing a purchase, in one transaction:
--   1. supplier credit applied to it is un-applied (the credit stays with the supplier)
--   2. supplier payments that paid ONLY this purchase are reversed (cash comes back)
--   3. money paid up front at purchase (its RawMaterialPurchase cash-out) comes
--      back to the same cash account as a new CashIn row -- the original row stays
--   4. the purchase's linked expense row is removed (as Delete did), so it no
--      longer counts as spend
--   5. stock: one opposite adjustment (movement type PurchaseReversal), the lot
--      emptied, and the row stamped Reversed with the reason. Nothing is deleted.
--
-- Refused while any of the lot has been used (production/medication/feed
-- production), while stock on hand is less than the purchase added, or while a
-- supplier payment on it also paid other items. Receipt lots (reverse the
-- receipt), feed-production lots (reverse the batch) and manual deferred cost
-- entries keep their own reversal paths.
--
-- sppoultryrawmaterialpurchase_delete is NOT changed: the API stops calling it.
-- Idempotent: ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE.

ALTER TABLE public.poultryrawmaterialpurchases ADD COLUMN IF NOT EXISTS reversalreason text;
ALTER TABLE public.poultryrawmaterialpurchases ADD COLUMN IF NOT EXISTS reversedby     text;


CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_reversalblockers(p_farmid text, p_purchaseid integer)
 RETURNS TABLE(code text, message text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_p       record;
    v_receipt text;
    v_used    text;
BEGIN
    SELECT pu.*, i.itemname, i.unitofmeasure, i.currentquantity
    INTO   v_p
    FROM   poultryrawmaterialpurchases pu
    JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    WHERE  pu.poultryrawmaterialpurchaseid = p_purchaseid AND pu.farmid = p_farmid;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'NotFound'::text, 'Purchase not found for this company.'::text;
        RETURN;
    END IF;
    IF v_p.reversedat IS NOT NULL THEN
        RETURN QUERY SELECT 'AlreadyReversed'::text, 'This purchase was already reversed.'::text;
        RETURN;
    END IF;
    IF COALESCE(v_p.lotsource, '') = 'ManualDeferredCost' THEN
        RETURN QUERY SELECT 'NotAPurchase'::text,
            'This is a manual deferred cost entry, not a purchase. Reverse it on Deferred Inventory Cost.'::text;
        RETURN;
    END IF;
    IF v_p.sourcefeedproductionbatchid IS NOT NULL THEN
        RETURN QUERY SELECT 'FeedProduction'::text,
            'This stock came from a feed production batch. Reverse the batch instead.'::text;
        RETURN;
    END IF;

    SELECT r.receiptnumber INTO v_receipt
    FROM   poultrypurchasereceiptlines rl
    JOIN   poultrypurchasereceipts r ON r.poultrypurchasereceiptid = rl.poultrypurchasereceiptid
    WHERE  rl.poultryrawmaterialpurchaseid = p_purchaseid
    LIMIT  1;
    IF v_receipt IS NOT NULL THEN
        RETURN QUERY SELECT 'ReceiptLot'::text,
            ('This purchase belongs to receipt ' || v_receipt || '. Reverse the receipt on Purchase Receipts.')::text;
        RETURN;
    END IF;

    -- Stock already used: name the records that used it.
    IF v_p.remainingquantity + 0.0005 < v_p.quantity
       OR COALESCE(v_p.deferredremainingcost, 0) + 0.005 < COALESCE(v_p.deferredtotalcost, 0) THEN
        SELECT string_agg(x.label, '; ' ORDER BY x.useddate) INTO v_used
        FROM (
            SELECT DISTINCT u.useddate,
                   (CASE WHEN u.productionrecordid IS NOT NULL THEN 'production record of '
                         WHEN u.poultryfeedproductionbatchid IS NOT NULL THEN 'feed production of '
                         ELSE 'usage of ' END)
                   || to_char(u.useddate, 'YYYY-MM-DD')
                   || ' (' || rtrim(to_char(ub.quantitydrawn, 'FM999999990.###'), '.') || ')' AS label
            FROM   poultryrawmaterialusagebatch ub
            JOIN   poultryrawmaterialusage u ON u.poultryrawmaterialusageid = ub.poultryrawmaterialusageid
            WHERE  ub.poultryrawmaterialpurchaseid = p_purchaseid
              AND  NOT COALESCE(u.isreversed, false)
            ORDER  BY u.useddate
            LIMIT  5
        ) x;

        RETURN QUERY SELECT 'Consumed'::text,
            (v_p.itemname || ': ' ||
             rtrim(to_char(v_p.quantity - v_p.remainingquantity, 'FM999999990.###'), '.') || ' of ' ||
             rtrim(to_char(v_p.quantity, 'FM999999990.###'), '.') ||
             ' from this purchase has already been used' ||
             COALESCE(' -- ' || v_used, '') ||
             '. Edit or delete those records first, then reverse the purchase.')::text;
    END IF;

    -- Stock on hand below what this purchase added (internal use or an
    -- adjustment took stock without drawing the lot).
    IF v_p.currentquantity + 0.0005 < v_p.quantity * COALESCE(NULLIF(v_p.productionunitsperpurchaseunit, 0), 1) THEN
        RETURN QUERY SELECT 'StockShort'::text,
            (v_p.itemname || ': only ' || rtrim(to_char(v_p.currentquantity, 'FM999999990.###'), '.') || ' ' ||
             COALESCE(v_p.unitofmeasure, '') || ' is in stock, but this purchase added ' ||
             rtrim(to_char(v_p.quantity * COALESCE(NULLIF(v_p.productionunitsperpurchaseunit, 0), 1), 'FM999999990.###'), '.') ||
             '. Reversing would leave stock wrong.')::text;
    END IF;

    -- A supplier payment that also paid other items (or holds unapplied credit).
    RETURN QUERY
    SELECT 'SharedPayment'::text,
           ('Supplier payment #' || s.paymentid::text ||
            ' also paid other items. Reverse it in Supplier Payments first.')::text
    FROM (
        SELECT sa.paymentid,
               (bool_and(sa.documenttype = 'RawMaterialPurchase' AND sa.documentid = p_purchaseid AND NOT sa.fromcredit)
                AND public.fnpoultrysupplierpayment_unapplied(p_farmid, sa.paymentid) <= 0.005) AS only_this
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
          AND  sa.paymentid IN (SELECT x.paymentid FROM supplierpaymentallocation x
                                WHERE x.farmid = p_farmid AND x.module = 'poultry' AND x.status = 'Posted'
                                  AND x.documenttype = 'RawMaterialPurchase' AND x.documentid = p_purchaseid
                                  AND NOT x.fromcredit)
        GROUP  BY sa.paymentid
    ) s
    WHERE NOT s.only_this;
END $function$;


CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_reverse(
    p_farmid text, p_purchaseid integer, p_reason text, p_reversedby text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_p     record;
    v_block text;
    v_note  text;
    v_gid   uuid;
    c       record;
    v_bal   numeric(14,2);
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'Give a reason for reversing this purchase.';
    END IF;

    SELECT pu.*, i.itemname INTO v_p
    FROM   poultryrawmaterialpurchases pu
    JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    WHERE  pu.poultryrawmaterialpurchaseid = p_purchaseid AND pu.farmid = p_farmid
    FOR UPDATE OF pu;

    SELECT b.message INTO v_block
    FROM   public.sppoultryrawmaterialpurchase_reversalblockers(p_farmid, p_purchaseid) b LIMIT 1;
    IF v_block IS NOT NULL THEN
        RAISE EXCEPTION '%', v_block;
    END IF;

    v_note := left('Purchase #' || p_purchaseid::text || ' reversed: ' || btrim(p_reason), 500);

    -- 1. Supplier credit applied to it goes back to the supplier.
    FOR c IN SELECT sa.allocationid FROM supplierpaymentallocation sa
             WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
               AND  sa.documenttype = 'RawMaterialPurchase' AND sa.documentid = p_purchaseid
               AND  sa.fromcredit LOOP
        PERFORM public.sppoultrysuppliercredit_unapply(p_farmid, c.allocationid, v_note, p_reversedby);
    END LOOP;

    -- 2. Supplier payments that paid only this purchase (the blocker refused shared ones).
    FOR c IN SELECT DISTINCT sa.paymentid FROM supplierpaymentallocation sa
             WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
               AND  sa.documenttype = 'RawMaterialPurchase' AND sa.documentid = p_purchaseid
               AND  NOT sa.fromcredit LOOP
        PERFORM public.sppoultrysupplierpayment_reverse(p_farmid, c.paymentid, v_note, p_reversedby);
    END LOOP;

    -- 3. Money paid up front at purchase: put it back, per account, as a new row.
    FOR c IN SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
             FROM   poultrycashtransactions ct
             WHERE  ct.farmid = p_farmid AND ct.sourcetype = 'RawMaterialPurchase' AND ct.sourceid = p_purchaseid
             GROUP  BY ct.poultrycashaccountid
             HAVING abs(SUM(ct.amount)) > 0.005 LOOP
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - c.net, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = c.poultrycashaccountid AND a.farmid = p_farmid
        RETURNING a.currentbalance INTO v_bal;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, c.poultrycashaccountid, (now() at time zone 'utc'), 'CashIn', 'RawMaterialPurchaseReversal', p_purchaseid,
             -c.net, v_bal, left('Reversal of purchase: ' || COALESCE(v_p.itemname, 'item') || ' -- ' || btrim(p_reason), 500),
             p_reversedby, p_reversedby, (now() at time zone 'utc'));
    END LOOP;

    -- 4. The purchase's expense row stops counting as spend.
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;
    IF v_gid IS NOT NULL THEN
        DELETE FROM expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = p_purchaseid;
    END IF;

    -- 5. Stock out, lot emptied, row kept and marked Reversed.
    PERFORM public.sppoultryrawmaterialitem_adjust(
        p_farmid, v_p.poultryrawmaterialitemid,
        -(v_p.quantity * COALESCE(NULLIF(v_p.productionunitsperpurchaseunit, 0), 1)),
        v_p.unitcost, 'PurchaseReversal',
        left('Reversal of purchase #' || p_purchaseid::text || ': ' || btrim(p_reason), 500),
        p_reversedby);

    UPDATE poultryrawmaterialpurchases pu
    SET    remainingquantity     = 0,
           deferredremainingcost = 0,
           reversedat            = (now() at time zone 'utc'),
           reversedby            = p_reversedby,
           reversalreason        = btrim(p_reason),
           updatedat             = (now() at time zone 'utc')
    WHERE  pu.poultryrawmaterialpurchaseid = p_purchaseid AND pu.farmid = p_farmid;
END $function$;

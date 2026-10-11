-- =============================================================================
-- 346  Cash Flow: money paid for stock whose cost waits for consumption
-- =============================================================================
--
-- THE GAP
-- -------
-- Poultry Cash Flow (sppoultrycashflow_rows, 235 -> 307) does not read the
-- cash ledger. It reads the EXPENSE table, on the reasoning (arm 3b's header)
-- that "a payment against a raw-material purchase ... books its own expense row
-- dated the payment date and is already counted by arm 3".
--
-- 262 broke that reasoning and its header did not notice: a purchase whose
-- method is EXPENSE_WHEN_CONSUMED books NO expense row -- not at entry, not
-- when a supplier payment settles it later -- because its cost is inventory
-- until it is used, and the consumption expense that eventually comes is
-- NonCash (excluded from Cash Flow by design). So the money paid for deferred
-- stock never appears in Cash Flow at all: not in Money Out, not in closing
-- cash, not in the Daily Closing's cash figure that reads the same summary.
-- On dev, 2026-10-01, that is 18,500.00 across two companies.
--
-- Purchase Receipts (345) make the gap routine rather than rare, since a farm
-- set to "expense when used" pays for every receipt this way.
--
-- THE FIX
-- -------
-- Two new arms, mirroring arms 3 and 3b for the deferred lots ONLY, so every
-- cedi is counted exactly once:
--
--   3c  InventoryPurchase         amountpaid recorded on the lot itself, less
--                                 what supplier payments cover, dated the
--                                 purchase date. Lots created by feed
--                                 production are left out: that money is the
--                                 FeedProduction cash event, not a purchase.
--   3d  InventoryPurchasePayment  each posted supplier-payment allocation to a
--                                 deferred lot, dated the payment date.
--
-- EXPENSE_WHEN_PURCHASED lots are untouched: their expense rows still carry the
-- cash through arm 3, exactly as before. A reversed payment's allocations are
-- Reversed and drop out of 3d; a reversed receipt's lots were never paid at
-- entry, so 3c never sees them.
--
-- Both arms report sourcetype 'RawMaterialPurchase', so _detail buckets them
-- under the "Raw materials" label the frontend already has.
--
-- Patched in place from the LIVE body (whitespace-tolerant, RAISEs if the
-- anchor has drifted) rather than re-pasting 684 lines that are only in the
-- database.
-- =============================================================================

BEGIN;

DO $p$
DECLARE
    v_def text;
    v_new text;
    v_arm text := $arm$

    -- ---- 3c. (346) paid at entry for stock expensed when USED ---------------
    -- A deferred lot books no expense, so arm 3 never sees its cash. Only
    -- the part not covered by a supplier payment (that is 3d's).
    RETURN QUERY
    SELECT 'InventoryPurchase'::text,
           FALSE,
           pu.poultryrawmaterialpurchaseid,
           pu.poultrycashaccountid,
           NULL::text,
           pu.purchasedate,
           'CashOut'::text,
           'RawMaterialPurchase'::text,
           pu.poultryrawmaterialpurchaseid,
           FALSE,
           -v.paidatentry,
           ('Stock purchase: ' || COALESCE(i.itemname, 'item'))::text,
           'OperatingOut'::text,
           pu.createdat
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    CROSS  JOIN LATERAL (
        SELECT GREATEST(
                   pu.amountpaid
                 - COALESCE((SELECT SUM(sa.amountapplied)
                             FROM   supplierpaymentallocation sa
                             WHERE  sa.farmid = p_farmid
                               AND  sa.module = 'poultry'
                               AND  sa.status = 'Posted'
                               AND  sa.documenttype = 'RawMaterialPurchase'
                               AND  sa.documentid = pu.poultryrawmaterialpurchaseid), 0)
               , 0)::numeric AS paidatentry
    ) v
    WHERE  pu.farmid = p_farmid
      AND  NOT fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)
      AND  pu.sourcefeedproductionbatchid IS NULL
      AND  v.paidatentry > 0
      AND  pu.purchasedate >= v_from
      AND  pu.purchasedate <= v_to;

    -- ---- 3d. (346) supplier payments for stock expensed when USED -----------
    RETURN QUERY
    SELECT 'InventoryPurchasePayment'::text,
           FALSE,
           sa.allocationid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'RawMaterialPurchase'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment for stock purchase' ||
            COALESCE(': ' || NULLIF(btrim(i.itemname), ''), '') ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sa.createdat
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON  sp.poultrysupplierpaymentid = sa.paymentid
           AND sp.farmid = sa.farmid
    JOIN   poultryrawmaterialpurchases pu
           ON  pu.poultryrawmaterialpurchaseid = sa.documentid
           AND pu.farmid = sa.farmid
    LEFT   JOIN poultryrawmaterialitems i
           ON  i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    LEFT   JOIN supplier s
           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'RawMaterialPurchase'
      AND  sp.status = 'Posted'
      AND  sa.amountapplied <> 0
      AND  NOT fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;
$arm$;
BEGIN
    v_def := pg_get_functiondef(
        'public.sppoultrycashflow_rows(text,timestamp without time zone,timestamp without time zone)'::regprocedure);

    IF v_def ~ '''InventoryPurchasePayment''' THEN
        RAISE NOTICE '346: sppoultrycashflow_rows already carries the deferred-purchase arms.';
        RETURN;
    END IF;

    -- Anchor: the end of arm 3b (the only arm filtering documenttype 'Expense'
    -- on a supplier-payment join).
    v_new := regexp_replace(v_def,
        '(AND\s+sa\.documenttype\s*=\s*''Expense''\s+AND\s+sp\.status\s*=\s*''Posted''\s+AND\s+sa\.amountapplied\s*<>\s*0\s+AND\s+sp\.paymentdate\s*>=\s*v_from\s+AND\s+sp\.paymentdate\s*<=\s*v_to\s*;)',
        '\1' || replace(v_arm, '\', '\\'));

    IF v_new = v_def THEN
        RAISE EXCEPTION '346: anchor (end of arm 3b) not found in sppoultrycashflow_rows -- the live body has drifted.';
    END IF;

    EXECUTE v_new;
END $p$;

COMMIT;

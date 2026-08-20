-- =============================================================================
-- 208 (PostgreSQL): backfill the expenses missed while 153/157 had the link cut
--
-- NOT RUN AUTOMATICALLY. This one moves money on the books — read it, decide,
-- then run it deliberately. Migration 207 restored the linked expense going
-- forward; this repairs the purchases recorded while the link was missing.
--
-- SCOPE (measured on VisibilityCoreDB, 2026-08-18, after 207)
--   54 purchases with amountpaid > 0 and no linked expense, totalling 380,962.00,
--   purchase dates 2026-06-30 .. 2026-08-18, across five farms:
--     7b95dafa-758f-4461-891d-f612131978fd   12 purchases   264,400.00
--     b55bf33e-a5ba-4d9b-a287-1dea39a84f13   31 purchases   105,790.00
--     bbffc4a1-bbf2-4606-8cc2-c684785814f0    2 purchases     6,122.00
--     3c4ac3cd-8792-4739-9b20-5f3b7d655a02    6 purchases     3,500.00
--     224f8096-7a9e-41b4-9c64-664b2a6e3c72    3 purchases     1,150.00
--
-- EFFECT
--   Cash at hand on /cash drops by the amount booked per farm, because /cash is
--   an all-time running balance of adjustments + paid sales - expenses. Daily
--   closing figures for the affected dates change too: each expense is dated to
--   its PURCHASE date, not today, so it lands in the day it actually belongs to.
--   Nothing else moves — stock, batch costing and cash accounts are untouched.
--
-- userid
--   expense.userid is NOT NULL. 52 of the 54 purchases carry createdby; the
--   other 2 (6,122.00) do not, so they fall back to the most recent userid that
--   has posted an expense on the same farm. If a farm has no expense history at
--   all the row is skipped rather than guessed — the final query reports any.
--
-- Idempotent: the NOT EXISTS guard means a second run inserts nothing.
--
-- Descriptions read exactly as a normally-posted purchase does — these rows are
-- the farm's real expenses and should not look like a maintenance artefact in
-- their expense list. The run is still identifiable without a marker: every row
-- inserted by one run shares a single createddate. Capture it before you need
-- it, and reverse with
--     DELETE FROM expense
--     WHERE  sourcetype = 'PoultryRawMaterialPurchase' AND createddate = '<ts>';
--
-- APPLIED to VisibilityCoreDB on 2026-08-18: 54 rows, expenseid 1168..1221,
-- createddate 2026-08-18 20:44:05.44466.
-- =============================================================================

BEGIN;

INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                     supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
SELECT pu.purchasedate,
       'Raw Materials / Inventory Purchase',
       'Raw material purchase: ' || COALESCE(i.itemname, 'item')
           || ' (' || pu.quantity::text || ' ' || COALESCE(i.unitofmeasure, '') || ')',
       pu.amountpaid,
       COALESCE(pu.paymentmethod, 'Cash'),
       pu.suppliername,
       NULL,
       (now() at time zone 'utc'),
       COALESCE(pu.createdby, fb.userid),
       pu.farmid::uuid,
       'PoultryRawMaterialPurchase',
       pu.poultryrawmaterialpurchaseid
FROM   poultryrawmaterialpurchases pu
LEFT   JOIN poultryrawmaterialitems i
       ON  i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
       AND i.farmid = pu.farmid
LEFT   JOIN LATERAL (
           -- Fallback userid: whoever last posted an expense on this farm.
           SELECT e2.userid
           FROM   expense e2
           WHERE  e2.farmid = pu.farmid::uuid
           ORDER  BY e2.createddate DESC
           LIMIT  1
       ) fb ON TRUE
WHERE  pu.amountpaid > 0
       AND COALESCE(pu.createdby, fb.userid) IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM expense e
           WHERE  e.sourcetype = 'PoultryRawMaterialPurchase'
                  AND e.sourceid = pu.poultryrawmaterialpurchaseid);

COMMIT;

-- ---- Verification ------------------------------------------------------------
-- What this run booked, per farm. Rows share one createddate, so the newest
-- such group is the run that just finished. Note the timestamp: it is the only
-- handle for reversing the run.
SELECT e.createddate, e.farmid, count(*) AS rows_booked, sum(e.amount) AS amount_booked,
       min(e.expensedate)::date AS earliest, max(e.expensedate)::date AS latest
FROM   expense e
WHERE  e.sourcetype = 'PoultryRawMaterialPurchase'
       AND e.createddate = (SELECT max(createddate) FROM expense
                            WHERE sourcetype = 'PoultryRawMaterialPurchase')
GROUP  BY e.createddate, e.farmid
ORDER  BY amount_booked DESC;

-- Every paid purchase should now have linked expenses summing to amountpaid.
SELECT count(*) AS purchases_out_of_balance FROM (
    SELECT pu.amountpaid,
           COALESCE((SELECT sum(e.amount) FROM expense e
                     WHERE e.sourcetype = 'PoultryRawMaterialPurchase'
                           AND e.sourceid = pu.poultryrawmaterialpurchaseid), 0) AS linked
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.amountpaid > 0) x
WHERE  x.linked <> x.amountpaid;

-- Should be empty. Anything here had no createdby and no expense history to
-- borrow a userid from, and needs a userid supplied by hand.
SELECT pu.poultryrawmaterialpurchaseid, pu.farmid, pu.purchasedate, pu.amountpaid
FROM   poultryrawmaterialpurchases pu
WHERE  pu.amountpaid > 0
       AND NOT EXISTS (SELECT 1 FROM expense e
                       WHERE e.sourcetype = 'PoultryRawMaterialPurchase'
                             AND e.sourceid = pu.poultryrawmaterialpurchaseid)
ORDER  BY pu.farmid, pu.purchasedate;

-- =============================================================================
-- 452_GenericDeferredInventoryCost.postgres.sql   (Report 40, Part 6)
--
-- Generic Deferred inventory cost, purchase by purchase, the way Poultry's and
-- Water's page shows it (lot rows, draw history, scope filters, summary).
--
-- Generic has no cost-layer tables: what it has is genericstockmovements, where
-- every stock change is a row with a quantity (+ in, - out) and its cost. A
-- product's cost reaches Profit & Loss when the stock is sold or used (COGS on
-- the sale; internal use and losses as their own lines), so until then it is
-- deferred. This file derives the lots from the movements -- READ-ONLY, nothing
-- is stored, nothing can drift:
--
--   LOT   = a movement that ADDS stock (opening stock, purchase, production
--           output, adjustment in, transfer in). Its cost is the movement's
--           cost; a purchase lot carries its supplier.
--   DRAW  = a movement that TAKES stock out (sale, internal use, delivery load,
--           damage, expiry, adjustment out, production use). A delivery
--           return / cancel or a return-in puts stock back: a negative draw.
--   Draws take the OLDEST stock first (FIFO), per product. A lot's expensed
--   cost = quantity drawn from it x the lot's unit cost.
--
-- Deploy order: this migration, then the Farm API, then the web app. Idempotent.
-- =============================================================================

-- The lots, with their place in the FIFO queue.
CREATE OR REPLACE FUNCTION public.fngenericdeferred_lots(p_farmid text)
RETURNS TABLE(lotid integer, genericproductid integer, lotdate timestamp, movementtype text,
              referencetype text, referenceid integer, quantity numeric, unitcost numeric, lotcost numeric,
              lotstart numeric, lotend numeric)
LANGUAGE sql STABLE AS $f$
    WITH l AS (
        SELECT m.genericstockmovementid, m.genericproductid, m.movementdate, m.movementtype::text,
               m.referencetype::text, m.referenceid, m.quantity::numeric AS qty,
               round(COALESCE(NULLIF(abs(m.totalcostvalue), 0) / NULLIF(m.quantity, 0), m.unitcost, 0)::numeric, 6) AS uc,
               round(COALESCE(NULLIF(abs(m.totalcostvalue), 0), m.quantity * COALESCE(m.unitcost, 0), 0)::numeric, 2) AS cost
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid AND m.quantity > 0
          AND  m.movementtype NOT IN ('Delivery Return', 'Delivery Cancel', 'ReturnIn')
    )
    SELECT l.genericstockmovementid, l.genericproductid, l.movementdate, l.movementtype, l.referencetype,
           l.referenceid, l.qty, l.uc, l.cost,
           COALESCE(SUM(l.qty) OVER w, 0) - l.qty, COALESCE(SUM(l.qty) OVER w, 0)
    FROM   l
    WINDOW w AS (PARTITION BY l.genericproductid ORDER BY l.movementdate, l.genericstockmovementid
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);
$f$;

-- Every draw (and give-back), positioned on the product's consumption line.
CREATE OR REPLACE FUNCTION public.fngenericdeferred_draws(p_farmid text)
RETURNS TABLE(movementid integer, genericproductid integer, drawdate timestamp, movementtype text,
              referencetype text, referenceid integer, quantity numeric, cstart numeric, cend numeric)
LANGUAGE sql STABLE AS $f$
    WITH d AS (
        SELECT m.genericstockmovementid, m.genericproductid, m.movementdate, m.movementtype::text,
               m.referencetype::text, m.referenceid, (-m.quantity)::numeric AS qty
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid
          AND  (m.quantity < 0 OR (m.quantity > 0 AND m.movementtype IN ('Delivery Return', 'Delivery Cancel', 'ReturnIn')))
    )
    SELECT d.genericstockmovementid, d.genericproductid, d.movementdate, d.movementtype, d.referencetype,
           d.referenceid, d.qty,
           SUM(d.qty) OVER w - d.qty, SUM(d.qty) OVER w
    FROM   d
    WINDOW w AS (PARTITION BY d.genericproductid ORDER BY d.movementdate, d.genericstockmovementid
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);
$f$;

-- What each draw took from each lot (negative for a give-back).
CREATE OR REPLACE FUNCTION public.fngenericdeferred_allocations(p_farmid text)
RETURNS TABLE(lotid integer, movementid integer, genericproductid integer, drawdate timestamp,
              movementtype text, referencetype text, referenceid integer, quantitydrawn numeric,
              unitcost numeric, recognized numeric)
LANGUAGE sql STABLE AS $f$
    SELECT l.lotid, d.movementid, d.genericproductid, d.drawdate, d.movementtype, d.referencetype, d.referenceid,
           q.qty, l.unitcost, round(q.qty * l.unitcost, 2)
    FROM   public.fngenericdeferred_draws(p_farmid) d
    JOIN   public.fngenericdeferred_lots(p_farmid) l ON l.genericproductid = d.genericproductid
    CROSS  JOIN LATERAL (
        SELECT CASE WHEN d.quantity >= 0
                    THEN GREATEST(0, LEAST(d.cend, l.lotend) - GREATEST(d.cstart, l.lotstart))
                    ELSE -GREATEST(0, LEAST(d.cstart, l.lotend) - GREATEST(d.cend, l.lotstart)) END AS qty
    ) q
    WHERE  q.qty <> 0;
$f$;

-- The page's rows (Poultry's PoultryDeferredPurchase shape, generic names).
CREATE OR REPLACE FUNCTION public.spgenericdeferredcost_lots(
    p_farmid text, p_scope text DEFAULT 'DEFERRED', p_productid integer DEFAULT NULL,
    p_supplierid integer DEFAULT NULL, p_category text DEFAULT NULL,
    p_fromdate timestamp DEFAULT NULL, p_todate timestamp DEFAULT NULL, p_search text DEFAULT NULL)
RETURNS TABLE(genericpurchaseid integer, lotid integer, purchasedate timestamp, genericproductid integer,
              itemname text, category text, unitofmeasure text, supplierid integer, suppliername text,
              lotsource text, purchasedquantity numeric, consumedquantity numeric, remainingquantity numeric,
              operationalcost numeric, recognizedcost numeric, deferredremainingcost numeric,
              recognitionpercent numeric, status text, recognitionevents integer, lastrecognitiondate timestamp,
              queueposition integer, quantityaheadinqueue numeric)
LANGUAGE sql STABLE AS $f$
    WITH a AS (
        SELECT al.lotid, SUM(al.quantitydrawn) AS drawn, SUM(al.recognized) AS rec,
               COUNT(*) FILTER (WHERE al.quantitydrawn > 0) AS events, MAX(al.drawdate) AS lastdraw
        FROM   public.fngenericdeferred_allocations(p_farmid) al GROUP BY al.lotid
    ), x AS (
        SELECT l.*, LEAST(GREATEST(COALESCE(a.drawn, 0), 0), l.quantity) AS consumed,
               LEAST(GREATEST(COALESCE(a.rec, 0), 0), l.lotcost) AS rec,
               COALESCE(a.events, 0) AS events, a.lastdraw,
               p.productname::text AS pname, c.name::text AS cat, p.unitofmeasure::text AS uom,
               pu.genericpurchaseid AS purchaseid, s.genericsupplierid AS supid, s.suppliername::text AS supname
        FROM   public.fngenericdeferred_lots(p_farmid) l
        LEFT   JOIN a ON a.lotid = l.lotid
        JOIN   genericproducts p ON p.genericproductid = l.genericproductid AND p.farmid = p_farmid
        LEFT   JOIN genericproductcategories c ON c.genericproductcategoryid = p.genericproductcategoryid
        LEFT   JOIN genericpurchases pu ON l.referencetype = 'Purchase' AND pu.genericpurchaseid = l.referenceid AND pu.farmid = p_farmid
        LEFT   JOIN genericsuppliers s ON s.genericsupplierid = pu.genericsupplierid
    ), y AS (
        SELECT x.*, x.quantity - x.consumed AS remaining,
               CASE WHEN x.quantity - x.consumed > 0
                    THEN (ROW_NUMBER() OVER (PARTITION BY x.genericproductid, (x.quantity - x.consumed > 0)
                                             ORDER BY x.lotdate, x.lotid))::int END AS qpos
        FROM   x
    )
    SELECT y.purchaseid, y.lotid, y.lotdate, y.genericproductid, y.pname, y.cat, y.uom, y.supid, y.supname,
           CASE y.movementtype WHEN 'PurchaseIn' THEN 'Purchase' WHEN 'OpeningStock' THEN 'Opening stock'
                WHEN 'Production' THEN 'Produced' WHEN 'AdjustmentIn' THEN 'Stock adjustment'
                WHEN 'TransferIn' THEN 'Transfer in' ELSE y.movementtype END,
           y.quantity, y.consumed, y.remaining,
           y.lotcost, y.rec, GREATEST(y.lotcost - y.rec, 0)::numeric(14,2),
           CASE WHEN y.lotcost > 0 THEN round(100 * y.rec / y.lotcost, 1) ELSE 0 END,
           CASE WHEN y.remaining <= 0 THEN 'Fully expensed'
                WHEN y.consumed > 0 THEN 'Partly expensed' ELSE 'Not yet expensed' END,
           y.events::int, y.lastdraw, y.qpos,
           CASE WHEN y.qpos IS NULL THEN NULL
                ELSE COALESCE((SELECT SUM(z.remaining) FROM y z
                               WHERE z.genericproductid = y.genericproductid AND z.qpos < y.qpos), 0) END
    FROM   y
    WHERE  (p_productid IS NULL OR y.genericproductid = p_productid)
      AND  (p_supplierid IS NULL OR y.supid = p_supplierid)
      AND  (p_category IS NULL OR y.cat = p_category)
      AND  (p_fromdate IS NULL OR y.lotdate >= p_fromdate)
      AND  (p_todate IS NULL OR y.lotdate < p_todate + interval '1 day')
      AND  (p_search IS NULL OR y.pname ILIKE '%' || p_search || '%' OR COALESCE(y.supname, '') ILIKE '%' || p_search || '%'
            OR ('#' || COALESCE(y.purchaseid, y.lotid)::text) ILIKE '%' || p_search || '%')
      AND  (COALESCE(upper(p_scope), 'DEFERRED') = 'ALL'
            OR (upper(p_scope) = 'DEFERRED'   AND y.remaining > 0)
            OR (upper(p_scope) = 'RECOGNIZED' AND y.remaining <= 0)
            OR (upper(p_scope) = 'EXCEPTION'  AND FALSE))
    ORDER  BY y.lotdate DESC, y.lotid DESC;
$f$;

-- One lot's draws (Poultry's recognition history shape).
CREATE OR REPLACE FUNCTION public.spgenericdeferredcost_history(p_farmid text, p_lotid integer)
RETURNS TABLE(movementid integer, useddate timestamp, sourcetype text, sourcelabel text, referenceid integer,
              itemname text, quantitydrawn numeric, unitcostatdraw numeric, operationalcost numeric,
              recognizedcost numeric, recognitionoutcome text)
LANGUAGE sql STABLE AS $f$
    SELECT al.movementid, al.drawdate, al.movementtype,
           (CASE al.movementtype
                WHEN 'SaleOut'          THEN 'Sale'
                WHEN 'InternalUseOut'   THEN 'Internal use'
                WHEN 'Delivery Load'    THEN 'Delivery load'
                WHEN 'Delivery Return'  THEN 'Delivery return'
                WHEN 'Delivery Cancel'  THEN 'Delivery cancelled'
                WHEN 'ReturnIn'         THEN 'Returned'
                WHEN 'DamageOut'        THEN 'Damaged'
                WHEN 'ExpiredOut'       THEN 'Expired'
                WHEN 'AdjustmentOut'    THEN 'Stock adjustment'
                WHEN 'TransferOut'      THEN 'Transfer out'
                WHEN 'Production'       THEN 'Used in production'
                ELSE al.movementtype END
             || CASE WHEN al.referenceid IS NOT NULL THEN ' #' || al.referenceid ELSE '' END)::text,
           al.referenceid, p.productname::text, al.quantitydrawn, al.unitcost,
           round(al.quantitydrawn * al.unitcost, 2), al.recognized,
           CASE WHEN al.quantitydrawn < 0 THEN 'Given back' ELSE 'Expensed' END::text
    FROM   public.fngenericdeferred_allocations(p_farmid) al
    JOIN   genericproducts p ON p.genericproductid = al.genericproductid
    WHERE  al.lotid = p_lotid
    ORDER  BY al.drawdate, al.movementid;
$f$;

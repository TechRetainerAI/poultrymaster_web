-- =============================================================================
-- 502_Enock_GenericStockMovementsWholeDay: the Stock Movements list's "To" date
-- covers the whole day.
-- =============================================================================
-- The page sends dates (2026-11-27), which arrive as midnight. "movementdate <=
-- midnight" dropped every movement made later that day with a time on it -- a
-- purchase reversal (500) at 10:28, a sale reversal (483), and so on -- while the
-- midnight-dated row it undid still showed. A "To" date at exactly midnight now
-- means "to the end of that day"; a "To" with a time is used as given.
-- Rebuilt from the live body. Read-only list: no business data changes.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericstockmovement_getbyfarm(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(genericstockmovementid integer, farmid text, genericproductid integer, productname text, inventorylocationid integer, movementdate timestamp without time zone, movementtype text, quantity numeric, unitcost numeric, unitsellingprice numeric, totalcostvalue numeric, referencetype text, referenceid integer, reason text, createdby text, approvedby text, approvedat timestamp without time zone, notes text, createdat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT m.genericstockmovementid, m.farmid::text, m.genericproductid, p.productname::text,
           m.inventorylocationid, m.movementdate, m.movementtype::text, m.quantity,
           m.unitcost, m.unitsellingprice, m.totalcostvalue,
           m.referencetype::text, m.referenceid, m.reason::text,
           m.createdby::text, m.approvedby::text, m.approvedat, m.notes::text, m.createdat
    FROM   genericstockmovements m
    INNER  JOIN genericproducts p ON p.genericproductid = m.genericproductid
    WHERE  m.farmid = p_farmid
       AND (p_fromdate IS NULL OR m.movementdate >= p_fromdate)
       AND (p_todate   IS NULL OR m.movementdate <= p_todate
            OR (p_todate = date_trunc('day', p_todate) AND m.movementdate < p_todate + interval '1 day'))   -- 502
    ORDER  BY m.movementdate DESC, m.genericstockmovementid DESC;
END
$function$;

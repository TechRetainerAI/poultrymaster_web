DROP FUNCTION IF EXISTS public.sppoultryreport_eggstockbalance(text, date, date);



CREATE FUNCTION public.sppoultryreport_eggstockbalance(p_farmid text, p_startdate date, p_enddate date)
 RETURNS TABLE(openingproducedsaleable bigint, openingadjustments bigint, openingsales bigint, productionadded bigint, brokeninrange bigint, adjustmentsinrange bigint, salesinrange bigint, openingstockmoves bigint, stockmovesinrange bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        -- Opening saleable eggs produced before the range
        COALESCE((SELECT SUM(r.totalproduction::bigint
                             - (COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)
                  FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date < p_startdate), 0)::bigint            AS openingproducedsaleable,
        COALESCE((SELECT SUM(a.eggdelta) FROM egginventoryadjustment a
                  WHERE a.farmid = p_farmid AND a.adjustmentdate < p_startdate), 0)::bigint  AS openingadjustments,
        -- Eggs sold before the range (reduces opening on-hand)
        COALESCE((SELECT SUM(trunc(s.quantity)::bigint) FROM sale s
                  WHERE s.farmid = p_farmid AND s.product ILIKE '%egg%' AND s.saledate < p_startdate), 0)::bigint AS openingsales,
        COALESCE((SELECT SUM(r.totalproduction::bigint) FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate), 0)::bigint AS productionadded,
        COALESCE((SELECT SUM((COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)
                  FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate), 0)::bigint AS brokeninrange,
        COALESCE((SELECT SUM(a.eggdelta) FROM egginventoryadjustment a
                  WHERE a.farmid = p_farmid AND a.adjustmentdate >= p_startdate AND a.adjustmentdate < (p_enddate + 1)), 0)::bigint AS adjustmentsinrange,
        -- Eggs sold within the range (reduces current on-hand)
        COALESCE((SELECT SUM(trunc(s.quantity)::bigint) FROM sale s
                  WHERE s.farmid = p_farmid AND s.product ILIKE '%egg%'
                    AND s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)), 0)::bigint AS salesinrange,
        -- Stock-ledger moves on the egg product that are neither production nor a
        -- sale: driver load-outs, deliveries, restocks and the Set stock /
        -- Reconcile corrections made from /poultry-inventory. Migration 204 made
        -- the ledger the single source of truth for egg stock; this report was the
        -- last figure still blind to these rows, which is why it disagreed with
        -- both /poultry-inventory and /egg-tracker. Production and Sale rows are
        -- excluded because they are already counted from the source tables above.
        COALESCE((SELECT SUM(trunc(t.quantity)::bigint)
                  FROM poultrystocktransactions t
                  JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
                  WHERE t.farmid = p_farmid
                    AND (COALESCE(p.israweggproduct,FALSE) = TRUE OR p.name IN ('Eggs','Chicken Eggs'))
                    AND t.txntype NOT IN ('Production','Sale')
                    AND t.createddate < p_startdate), 0)::bigint AS openingstockmoves,
        COALESCE((SELECT SUM(trunc(t.quantity)::bigint)
                  FROM poultrystocktransactions t
                  JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
                  WHERE t.farmid = p_farmid
                    AND (COALESCE(p.israweggproduct,FALSE) = TRUE OR p.name IN ('Eggs','Chicken Eggs'))
                    AND t.txntype NOT IN ('Production','Sale')
                    AND t.createddate >= p_startdate AND t.createddate < (p_enddate + 1)), 0)::bigint AS stockmovesinrange;
END
$function$;

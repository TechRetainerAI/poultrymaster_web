-- 480: Stock Movements shows the Batch / Flock of rows posted by a production record.
--
-- A production record posts its stock with relatedid = productionrecords.id:
--   Production (good eggs)              -- sppoultryeggstock_syncforproduction
--   Broken Egg Prod / Broken Egg Disposal,
--   Mortality In / Mortality Disposal   -- sppoultrybyproduct_syncforproduction
--   Mortality (older production rows)
-- None of them stamps batchid / flockid on the stock row, so the page's
-- Batch / Flock column was blank and its flock filter missed them.
--
-- Fixed in the READER only. Those columns are read by the bird ledger, flock
-- delete blockers, closing report, byproduct ledger and others; stamping them
-- now could change what those count. Here the flock comes from the record
-- (which can be edited, so the record is the authority anyway) and the batch
-- from the flock. A row whose record was deleted stays blank, as before.
--
-- Read-only: no table or row changes. Same signature as the live function.

CREATE OR REPLACE FUNCTION public.sppoultrystock_gettransactions(p_farmid text, p_poultryproductid integer DEFAULT NULL::integer)
 RETURNS TABLE(poultrystocktransactionid integer, farmid text, poultryproductid integer, txntype text, quantity numeric, unitcost numeric, relatedid integer, note text, createddate timestamp without time zone, createdby text, productname text, batchid integer, batchcode text, flockid integer, flockname text, effectivedate date, reason text, manualmovementid integer, manualreversal boolean, birdscope text, postedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH t AS (
        SELECT x.*,
               ROW_NUMBER() OVER (PARTITION BY x.farmid, x.txntype, x.relatedid
                                  ORDER BY x.poultrystocktransactionid) AS rn,
               -- 480: the production record behind the row, when it came from one.
               CASE WHEN x.manualmovementid IS NULL
                     AND x.flockid IS NULL
                     AND x.txntype IN ('Production', 'Broken Egg Prod', 'Broken Egg Disposal',
                                       'Mortality In', 'Mortality Disposal', 'Mortality')
                    THEN x.relatedid END AS productionrecordid
        FROM   poultrystocktransactions x
        WHERE  x.farmid = p_farmid
          AND  (p_poultryproductid IS NULL OR x.poultryproductid = p_poultryproductid)
    ), s AS (
        SELECT t.*,
               COALESCE(t.flockid, pr.flockid) AS shownflockid,
               COALESCE(t.batchid, CASE WHEN t.flockid IS NULL THEN pf.batchid END) AS shownbatchid
        FROM   t
        LEFT   JOIN productionrecords pr ON pr.id = t.productionrecordid AND pr.farmid = t.farmid
        LEFT   JOIN flock pf ON pf.flockid = pr.flockid
    )
    SELECT t.poultrystocktransactionid, t.farmid::text, t.poultryproductid, t.txntype::text,
           t.quantity, t.unitcost, t.relatedid, t.note::text, t.createddate, t.createdby::text,
           p.name::text AS productname,
           t.shownbatchid, b.batchcode::text, t.shownflockid, f.name::text, t.effectivedate, t.reason,
           t.manualmovementid, t.manualreversal,
           t.birdscope,
           COALESCE(
               t.postedat,
               CASE WHEN t.createddate <> date_trunc('day', t.createddate) THEN t.createddate END,
               CASE WHEN t.rn = 1 AND t.txntype = 'Opening Adjustment' THEN o.createdat END,
               CASE WHEN t.rn = 1 AND t.txntype = 'Bird Batch Purchase' THEN pb.createddate END,
               CASE WHEN t.rn = 1 AND t.txntype IN ('Flock Cull', 'Flock Transfer Out') THEN d.createdat END
           ) AS postedat
    FROM   s t
    INNER  JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
    LEFT   JOIN mainflockbatch b ON b.batchid = t.shownbatchid
    LEFT   JOIN flock f ON f.flockid = t.shownflockid
    LEFT   JOIN poultryopeningflockposition o
           ON t.txntype = 'Opening Adjustment' AND o.openingpositionid = t.relatedid AND o.farmid = t.farmid
    LEFT   JOIN mainflockbatch pb
           ON t.txntype = 'Bird Batch Purchase' AND pb.batchid = t.relatedid AND pb.farmid = t.farmid
    LEFT   JOIN flockcloseoutdispositions d
           ON t.txntype IN ('Flock Cull', 'Flock Transfer Out') AND d.dispositionid = t.relatedid AND d.farmid = t.farmid
    ORDER  BY t.createddate DESC, t.poultrystocktransactionid DESC;
END;
$function$;

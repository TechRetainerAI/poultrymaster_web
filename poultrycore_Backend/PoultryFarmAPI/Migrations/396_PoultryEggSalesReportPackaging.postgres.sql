-- =============================================================================
-- 396: Egg packaging, reports -- the Egg Sales report knows what was SOLD as
-- boxes, crates and pieces. Needs 394.
--
-- sppoultryreport_eggsales_rs1 (live body = 361) gains trailing columns: the
-- line number and the line's packaging snapshot (394). The report can then
-- answer both questions the spec separates:
--   A. How many boxes were ACTUALLY sold?  -> sum of qtyboxes on lines that
--      were entered in boxes (a line of 14 crates sold 0 boxes).
--   B. What is the quantity in EQUIVALENT boxes? -> total eggs / today's box
--      size, computed by the API and labelled as an equivalent.
-- Lines posted before 394 have NULL packaging: they count in B, never in A.
--
-- Same rows, same order, same filters; only columns are added, so every total
-- the report showed before is unchanged.
--
-- Idempotent: safe to run twice (drops and recreates the one function).
-- =============================================================================

DO $pre$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'saleline' AND column_name = 'qtyboxes') THEN
        RAISE EXCEPTION '396 needs 394 (packaged egg sales) first.';
    END IF;
END;
$pre$;

DROP FUNCTION IF EXISTS public.sppoultryreport_eggsales_rs1(text, date, date, integer, text);
CREATE FUNCTION public.sppoultryreport_eggsales_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_customername text DEFAULT NULL::text)
 RETURNS TABLE(date date, saleid integer, customer text, product text, size text, quantitysold numeric, unitprice numeric, totalamount numeric, paid boolean, amountpaid numeric, paymentmethod text, flockid integer,
               lineno integer, qtyboxes integer, qtycrates integer, qtypieces integer, eggspercrate integer, cratesperbox integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        s.saledate::date                AS date,
        s.saleid                        AS saleid,
        s.customername::text            AS customer,
        l.product::text                 AS product,
        l.size::text                    AS size,
        l.quantity                      AS quantitysold,
        l.unitprice                     AS unitprice,
        l.totalamount                   AS totalamount,
        COALESCE(s.paid, TRUE)          AS paid,
        CASE WHEN COALESCE(s.paid, TRUE) THEN l.totalamount
             WHEN s.totalamount > 0 THEN round(COALESCE(s.amountpaid, 0) * l.totalamount / s.totalamount, 2)
             ELSE 0 END                 AS amountpaid,
        s.paymentmethod::text           AS paymentmethod,
        s.flockid                       AS flockid,
        -- 396: the line and how it was entered (NULL before 394)
        l.lineno                        AS lineno,
        l.qtyboxes                      AS qtyboxes,
        l.qtycrates                     AS qtycrates,
        l.qtypieces                     AS qtypieces,
        l.eggspercrate                  AS eggspercrate,
        l.cratesperbox                  AS cratesperbox
    FROM   sale s
    JOIN   saleline l ON l.saleid = s.saleid
    WHERE  s.status = 'Posted' AND s.farmid = p_farmid
      AND  s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
      AND  (p_flockid IS NULL OR s.flockid = p_flockid)
      AND  (p_customername IS NULL OR s.customername = p_customername)
      AND  COALESCE(l.product, '') ILIKE '%egg%'
    ORDER  BY s.saledate DESC, s.saleid DESC, l.lineno;
END
$function$;
